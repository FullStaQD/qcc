// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// `magic-layer` in two halves: a pure core that turns a list of gates on ions into a list of layers, and an analysis /
// emitter pair around it that reads the gates off a function and emits the layers in their place.
//
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/IR/Magic.h"
#include "qcc/Dialect/Magic/Transforms/Passes.h" // IWYU pragma: keep
#include "qcc/Dialect/Utils/RotationUtils.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/ErrorHandling.h"

#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <map>
#include <optional>
#include <utility>
#include <variant>

using namespace mlir;

namespace qcc::magic {

#define GEN_PASS_DEF_MAGICLAYER
#include "qcc/Dialect/Magic/Transforms/Passes.h.inc"

//===----------------------------------------------------------------------===//
// Gate model
//===----------------------------------------------------------------------===//

namespace {

/// An ion, by id.
using Ion = int64_t;

/// `zxz` on one ion.
struct ZXZGate {
  Ion ion;
  ZXZAngles zxz;
};

/// `rz` on one ion.
struct RZGate {
  Ion ion;
  double angle;
};

/// `rzz(angle)` between the ions of `ions`, a pair `(i, j)` with `i < j`; `angle` is never zero.
struct ZZGate {
  std::pair<Ion, Ion> ions;
  double angle;
};

/// One gate of the input program, in the gate set the pass understands.
using Gate = std::variant<ZXZGate, RZGate, ZZGate>;

/// An SQ layer: the rotation each ion receives.
using SQLayer = std::map<Ion, ZXZAngles>;

/// A ZZ layer: the angle of each coupled pair `(i, j)` with `i < j`.
using ZZLayer = std::map<std::pair<Ion, Ion>, double>;

/// An SQ layer followed by a ZZ layer.
struct Round {
  SQLayer sq;
  ZZLayer zz;
};

/// The layers of a schedule: SQ and ZZ layers strictly alternating, starting with SQ. Layer `index` is an SQ layer if
/// `index` is even, else a ZZ layer. They are stored in rounds of two, so the alternation holds by construction, and
/// the accessors check that `index` is of the requested kind.
class Layers {
public:
  static bool isSQIndex(int64_t index) { return index % 2 == 0; }

  /// SQ layer `index`, creating its round if it is the next one.
  SQLayer& sq(int64_t index) {
    assert(index >= 0 && isSQIndex(index) && "not an SQ layer");
    return roundAt(index).sq;
  }

  /// ZZ layer `index`, creating its round if it is the next one.
  ZZLayer& zz(int64_t index) {
    assert(index >= 0 && !isSQIndex(index) && "not a ZZ layer");
    return roundAt(index).zz;
  }

  [[nodiscard]] ArrayRef<Round> getRounds() const { return rounds; }

  /// Whether every layer holds a gate, except that the first round may open with an empty SQ layer and the last one
  /// may end with an empty ZZ layer (but no round is empty), and no coupling has a zero angle. An empty layer between
  /// two others would mean that these two could have been one.
  [[nodiscard]] bool isCompact() const {
    return llvm::all_of(llvm::enumerate(rounds), [&](auto item) {
      auto [pos, round] = item;
      const bool sqValid = !round.sq.empty() || (pos == 0 && !round.zz.empty());
      const bool zzValid = !round.zz.empty() || (pos + 1 == rounds.size() && !round.sq.empty());
      return sqValid && zzValid && !llvm::is_contained(llvm::make_second_range(round.zz), 0.0);
    });
  }

private:
  Round& roundAt(int64_t index) {
    const auto pos = static_cast<size_t>(index / 2);
    assert(pos <= rounds.size() && "a round would be skipped");
    if (pos == rounds.size()) {
      rounds.emplace_back();
    }
    return rounds[pos];
  }

  SmallVector<Round> rounds;
};

/// Used by the emitter to generate the final IR.
struct Schedule {
  Layers layers;
  /// Diagonal rotations that never met a `zxz` on their ion; emitted as one `rz` per trap after the layers.
  std::map<Ion, double> residualRZ;
};

} // namespace

//===----------------------------------------------------------------------===//
// Core: gates -> layers
//===----------------------------------------------------------------------===//

/// One greedy pass of `layerGates`: schedules `gates` (in program order) into alternating layers.
///
/// The pass tracks `last[i]`, the index of the latest layer with a gate on (ion) `i`, `lastSQ[i]`, the latest SQ layer
/// with a gate on `i`, and `pending[i]`, an `rz` angle seen but not yet placed. Rules:
///
/// - `rz`: only accumulates in `pending`. Being diagonal it commutes with every ZZ layer, so it floats until the next
///   `zxz` on its ion absorbs it, or the end is reached.
/// - `zxz`: first absorbs `pending`. If the latest layer on `i` is an SQ layer the two rotations fuse (nothing touches
///   `i` in between); otherwise it goes into the first SQ layer after `last[i]`.
/// - `zz`: goes into the earliest ZZ layer it commutes back to.
/// - At the end, every `pending` rotation is folded into `lastSQ[i]` if there is one (only diagonal gates on `i` follow
///   it, so it commutes back); the rest becomes `residualRZ`.
///
/// Sets the bits of `cancelled`, one per gate, of the couplings that cancel out: those of a pair whose angles add up to
/// zero in its ZZ layer.
static Schedule layerGatesOnce(ArrayRef<Gate> gates, llvm::BitVector& cancelled) {
  assert(cancelled.size() == gates.size() && "one bit per gate");
  Schedule schedule;
  Layers& layers = schedule.layers;
  DenseMap<Ion, int64_t> last;
  DenseMap<Ion, int64_t> lastSQ;
  DenseMap<Ion, double> pending;
  // The positions in `gates` of the couplings in each ZZ layer, by layer index and pair.
  std::map<std::pair<int64_t, std::pair<Ion, Ion>>, SmallVector<size_t>> couplings;

  auto lastLayer = [&](Ion ion) { return last.lookup_or(ion, -1); };

  auto lastSQLayer = [&](Ion ion) { return lastSQ.lookup_or(ion, -1); };

  auto takePending = [&](Ion ion) -> std::optional<double> {
    auto it = pending.find(ion);
    if (it == pending.end()) {
      return std::nullopt;
    }
    const double angle = it->second;
    pending.erase(it);
    return angle;
  };

  auto addRZ = [&](const RZGate& gate) { pending[gate.ion] += gate.angle; };

  auto addZXZ = [&](const ZXZGate& gate) {
    const Ion ion = gate.ion;
    ZXZAngles zxz = gate.zxz;
    if (std::optional<double> angle = takePending(ion)) {
      zxz = fuseZXZ(*angle, zxz);
    }

    int64_t index = lastLayer(ion);
    if (index >= 0 && Layers::isSQIndex(index)) {
      ZXZAngles& existing = layers.sq(index).at(ion);
      existing = fuseZXZ(existing, zxz);
    } else {
      index += 1;
      layers.sq(index).emplace(ion, zxz);
    }
    last[ion] = index;
    lastSQ[ion] = index;
  };

  auto addZZ = [&](const ZZGate& gate, size_t pos) {
    const auto [ionA, ionB] = gate.ions;
    // The first ZZ layer after the latest SQ layer on either ion (layer 1 if there is none): the coupling commutes back
    // over everything else on its ions.
    const int64_t index = std::max({lastSQLayer(ionA), lastSQLayer(ionB), int64_t{0}}) + 1;
    layers.zz(index)[gate.ions] += gate.angle;
    couplings[{index, gate.ions}].push_back(pos);
    // Either ion may already be in a later ZZ layer.
    last[ionA] = std::max(lastLayer(ionA), index);
    last[ionB] = std::max(lastLayer(ionB), index);
  };

  for (size_t pos = 0; pos < gates.size(); ++pos) {
    std::visit(llvm::makeVisitor(addRZ, addZXZ, [&](const ZZGate& gate) { addZZ(gate, pos); }), gates[pos]);
  }

  for (const auto& [key, positions] : couplings) {
    const auto& [index, ions] = key;
    if (layers.zz(index).at(ions) == 0.0) {
      for (const size_t pos : positions) {
        cancelled.set(pos);
      }
    }
  }

  for (const auto& [ion, angle] : pending) {
    auto it = lastSQ.find(ion);
    if (it == lastSQ.end()) {
      schedule.residualRZ[ion] = angle;
      continue;
    }
    ZXZAngles& existing = layers.sq(it->second).at(ion);
    existing = fuseZXZ(existing, angle);
  }

  return schedule;
}

/// Schedules `gates` (in program order) into alternating layers by greedy passes, see `layerGatesOnce`. After each pass
/// it is possible that ZZ gates cancel; if that is the case, we repeat and only stop once nothing cancels anymore.
///
/// Measurements do not take part: `mzd` consumes its chain, so nothing follows it on its ions, and all of them go after
/// the last layer.
static Schedule layerGates(ArrayRef<Gate> gates) {
  SmallVector<Gate> kept = llvm::to_vector(gates);
  while (true) {
    llvm::BitVector cancelled(kept.size());
    Schedule schedule = layerGatesOnce(kept, cancelled);
    if (cancelled.none()) {
      assert(schedule.layers.isCompact() && "an empty layer between two others, or a coupling with a zero angle");
      return schedule;
    }
    // Every pass that does not return drops at least two gates, so this terminates.
    SmallVector<Gate> next;
    for (auto [pos, gate] : llvm::enumerate(kept)) {
      if (!cancelled.test(pos)) {
        next.push_back(gate);
      }
    }
    kept = std::move(next);
  }
}

//===----------------------------------------------------------------------===//
// Analysis: function -> gates
//===----------------------------------------------------------------------===//

static SmallVector<double> toDoubles(ArrayAttr angles) {
  return llvm::map_to_vector(angles.getAsValueRange<FloatAttr>(),
                             [](const APFloat& angle) { return angle.convertToDouble(); });
}

namespace {

/// Everything the emitter needs besides the schedule.
class Program {
public:
  /// Appends the gates `op` denotes to `gates` and records `op` in `gateOps`, so that the layers replace it.
  void addGateOp(Operation* op) {
    collectGates(op);
    gateOps.push_back(op);
  }

  /// The one `magic.init` of the function, null if there is none.
  InitOp init;
  /// Whether the function holds a magic op of a later stage (e.g. `sym_zxz`, `shuttle`), so it is past layering.
  bool pastLayering = false;
  /// The gates in program order, see `collectGates`.
  SmallVector<Gate> gates;
  /// The ops the gates were read from, in program order. The layers replace them.
  SmallVector<Operation*> gateOps;
  /// The measurements in program order. They move behind the layers.
  SmallVector<MZDOp> measurements;

private:
  /// Appends the gates `op` denotes to `gates`: one per ion for single-qubit gates, one per coupled pair for ZZ gates.
  /// Couplings with a zero angle are left out, so that they do not constrain the schedule.
  void collectGates(Operation* op) {
    llvm::TypeSwitch<Operation*>(op)
        .Case([&](ZXZOp zxz) {
          for (auto [ion, z1, x, z2] :
               llvm::zip_equal(zxz.getIons(), toDoubles(zxz.getZ1()), toDoubles(zxz.getX()), toDoubles(zxz.getZ2()))) {
            gates.push_back(ZXZGate{.ion = ion, .zxz = ZXZAngles{.z1 = z1, .x = x, .z2 = z2}});
          }
        })
        .Case([&](RZOp rz) {
          for (auto [ion, angle] : llvm::zip_equal(rz.getIons(), toDoubles(rz.getAngles()))) {
            gates.push_back(RZGate{.ion = ion, .angle = angle});
          }
        })
        .Case([&](ActiveZZOp zz) {
          // The matrix is symmetric with a zero diagonal, so the upper triangle holds every coupling. The active ions
          // are in position order, not sorted by id.
          const SmallVector<Ion> ions = zz.getChainIn().getType().getActiveIons();
          const SmallVector<double> matrix = llvm::to_vector(zz.getAngles().getValues<double>());
          const size_t n = ions.size();
          for (size_t i = 0; i < n; ++i) {
            for (size_t j = i + 1; j < n; ++j) {
              const double angle = matrix[(i * n) + j];
              if (angle != 0.0) {
                gates.push_back(ZZGate{.ions = std::minmax(ions[i], ions[j]), .angle = angle});
              }
            }
          }
        })
        .Case([&](InterTrapZZOp zz) {
          const double angle = zz.getAngle().convertToDouble();
          if (angle != 0.0) {
            const ArrayRef<Ion> ions = zz.getIons();
            gates.push_back(ZZGate{.ions = std::minmax(ions[0], ions[1]), .angle = angle});
          }
        })
        // Otherwise `op` would be replaced without its gates.
        .Default([](Operation*) { llvm_unreachable("not a gate op"); });
  }
};

} // namespace

/// Whether `op` takes or yields an ion chain.
static bool touchesChains(Operation* op) {
  auto isChain = [](Type type) { return isa<IonChainType>(type); };
  return llvm::any_of(op->getOperandTypes(), isChain) || llvm::any_of(op->getResultTypes(), isChain);
}

/// Reads `op` into `program`, or fails with a diagnostic naming the pass `passName`.
static LogicalResult analyzeOp(Operation* op, Program& program, StringRef passName) {
  return llvm::TypeSwitch<Operation*, LogicalResult>(op)
      .Case([&](InitOp init) -> LogicalResult {
        if (program.init) {
          return init.emitOpError() << "is the second 'magic.init' of the program: expected at most one";
        }
        program.init = init;
        return success();
      })
      .Case<ZXZOp, RZOp, ActiveZZOp, InterTrapZZOp>([&](Operation* gate) {
        program.addGateOp(gate);
        return success();
      })
      .Case([&](MZDOp mzd) {
        program.measurements.push_back(mzd);
        return success();
      })
      .Default([&](Operation* other) -> LogicalResult {
        if (isa_and_present<MagicDialect>(other->getDialect())) {
          program.pastLayering = true;
          return success();
        }
        // Magic ops sit directly in the function, but a nested non-magic op may still use a chain.
        const WalkResult walk = other->walk([&](Operation* nested) {
          if (!touchesChains(nested)) {
            return WalkResult::advance();
          }
          nested->emitOpError() << "is not a magic op but uses an ion chain, which " << passName << " does not support";
          return WalkResult::interrupt();
        });
        return failure(walk.wasInterrupted());
      });
}

/// Reads `block` into a `Program`, or fails with a diagnostic naming the pass `passName`.
static FailureOr<Program> analyzeBlock(Block& block, StringRef passName) {
  Program program;
  for (Operation& op : block) {
    if (failed(analyzeOp(&op, program, passName))) {
      return failure();
    }
  }
  return program;
}

//===----------------------------------------------------------------------===//
// Emitter: schedule -> layers behind `magic.init`
//===----------------------------------------------------------------------===//

namespace {

/// Emits the layers right behind `magic.init` and keeps the current chain value per trap: every emitted op continues
/// the chain of its trap. Without shuttles every ion stays in the trap `magic.init` puts it in, and without recodes
/// every ion stays active.
class LayerEmitter {
public:
  LayerEmitter(InitOp init, Location loc) : builder(init->getContext()), loc(loc) {
    builder.setInsertionPointAfter(init);
    for (Value value : init.getChains()) {
      auto chain = cast<TypedValue<IonChainType>>(value);
      const int64_t trap = chain.getType().getTrap();
      for (const Ion ion : chain.getType().getIons()) {
        trapOf[ion] = trap;
      }
      chains.emplace(trap, chain);
    }
  }

  /// One `zxz` per trap.
  void emitSQLayer(const SQLayer& zxzs) {
    for (auto& [trap, chain] : chains) {
      SmallVector<Ion> ions;
      SmallVector<double> z1;
      SmallVector<double> x;
      SmallVector<double> z2;
      for (const auto& [ion, zxz] : zxzs) {
        if (trapOf.at(ion) == trap) {
          ions.push_back(ion);
          z1.push_back(zxz.z1);
          x.push_back(zxz.x);
          z2.push_back(zxz.z2);
        }
      }
      if (!ions.empty()) {
        chain = ZXZOp::create(builder, loc, chain, ions, z1, x, z2);
      }
    }
  }

  /// One `active_zz` per trap over its active ions, then one `inter_trap_zz` per coupling across traps.
  void emitZZLayer(const ZZLayer& couplings) {
    for (auto& [trap, chain] : chains) {
      const SmallVector<Ion> active = chain.getType().getActiveIons();
      const int64_t n = std::ssize(active);
      auto position = [&](Ion ion) { return llvm::find(active, ion) - active.begin(); };
      SmallVector<double> matrix(n * n, 0.0);
      bool nonzero = false;
      for (const auto& [pair, angle] : couplings) {
        if (trapOf.at(pair.first) != trap || trapOf.at(pair.second) != trap) {
          continue;
        }
        const int64_t i = position(pair.first);
        const int64_t j = position(pair.second);
        matrix[(i * n) + j] = angle;
        matrix[(j * n) + i] = angle;
        nonzero = true;
      }
      if (nonzero) {
        auto type = RankedTensorType::get({n, n}, Float64Type::get(builder.getContext()));
        chain =
            ActiveZZOp::create(builder, loc, chain.getType(), chain, DenseElementsAttr::get(type, ArrayRef(matrix)));
      }
    }

    // Every `pair` is already sorted (see `ZZLayer`), as `inter_trap_zz` requires.
    for (const auto& [pair, angle] : couplings) {
      const auto [ionA, ionB] = pair;
      const int64_t trapA = trapOf.at(ionA);
      const int64_t trapB = trapOf.at(ionB);
      if (trapA == trapB) {
        continue;
      }
      TypedValue<IonChainType>& chainA = chains.at(trapA);
      TypedValue<IonChainType>& chainB = chains.at(trapB);
      auto zz = InterTrapZZOp::create(builder, loc, chainA.getType(), chainB.getType(), chainA, chainB,
                                      builder.getDenseI64ArrayAttr({ionA, ionB}), builder.getF64FloatAttr(angle));
      chainA = zz.getAOut();
      chainB = zz.getBOut();
    }
  }

  /// One `rz` per trap.
  void emitResidualRZ(const std::map<Ion, double>& residual) {
    for (auto& [trap, chain] : chains) {
      SmallVector<Ion> ions;
      SmallVector<double> angles;
      for (const auto& [ion, angle] : residual) {
        if (trapOf.at(ion) == trap) {
          ions.push_back(ion);
          angles.push_back(normalizeAngle(angle));
        }
      }
      if (!ions.empty()) {
        chain = RZOp::create(builder, loc, chain, ions, angles);
      }
    }
  }

  /// Moves `mzd` behind everything emitted so far, onto the current chain of its trap.
  void emitMeasurement(MZDOp mzd) {
    const TypedValue<IonChainType> chain = chains.at(mzd.getChain().getType().getTrap());
    // A no-op if `mzd` is the insertion point itself, which is why the insertion point moves behind it explicitly.
    mzd->moveBefore(builder.getInsertionBlock(), builder.getInsertionPoint());
    builder.setInsertionPointAfter(mzd);
    mzd.getChainMutable().assign(chain);
  }

private:
  OpBuilder builder;
  Location loc;
  /// The current chain value per trap, by trap id.
  std::map<int64_t, TypedValue<IonChainType>> chains;
  /// The trap of every ion.
  DenseMap<Ion, int64_t> trapOf;
};

} // namespace

/// Replaces the gates of `program` by the layers of `schedule` and moves the measurements behind them. Everything else
/// stays where it is (meaning: it comes after the measurements).
static void rebuild(const Program& program, const Schedule& schedule, Location loc) {
  LayerEmitter emitter(program.init, loc);
  for (const Round& round : schedule.layers.getRounds()) {
    emitter.emitSQLayer(round.sq);
    emitter.emitZZLayer(round.zz);
  }
  emitter.emitResidualRZ(schedule.residualRZ);
  for (MZDOp mzd : program.measurements) {
    emitter.emitMeasurement(mzd);
  }
  // In reverse, so that every op is unused when it goes: its successor on the chain went before it.
  for (Operation* op : llvm::reverse(program.gateOps)) {
    op->erase();
  }
}

//===----------------------------------------------------------------------===//
// Pass
//===----------------------------------------------------------------------===//

namespace {

struct MagicLayer final : impl::MagicLayerBase<MagicLayer> {
  using MagicLayerBase::MagicLayerBase;

protected:
  void runOnOperation() override {
    func::FuncOp func = getOperation();
    if (func.isExternal()) {
      return;
    }
    const FailureOr<Program> program = analyzeBlock(func.front(), getArgument());
    if (failed(program)) {
      return signalPassFailure();
    }
    if (program->init == nullptr || program->pastLayering) {
      return; // Nothing quantum to schedule here, or not any more.
    }
    rebuild(*program, layerGates(program->gates), func.getLoc());
  }
};

} // namespace
} // namespace qcc::magic
