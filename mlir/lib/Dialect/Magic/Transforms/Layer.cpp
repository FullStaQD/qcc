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
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Sequence.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/TypeSwitch.h"

#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <map>
#include <optional>
#include <utility>

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

/// One gate of the input program, in the gate set the pass understands.
struct Gate {
  enum class Kind : uint8_t {
    ZXZ, ///< `zxz` on one ion: `ions[0]`, `zxz`.
    RZ,  ///< `rz` on one ion: `ions[0]`, `angle`.
    ZZ,  ///< `active_zz` or `inter_trap_zz`: the row-major `matrix` over `ions`.
  };

  Kind kind;
  SmallVector<Ion> ions;
  ZXZAngles zxz;
  double angle = 0.0;
  SmallVector<double> matrix;
};

/// One layer of the schedule. Layers strictly alternate between the two kinds, starting with `SQ` (which may be
/// empty if the program opens with a coupling).
struct Layer {
  enum class Kind : uint8_t {
    SQ, ///< A `zxz` per trap over the ions in `sq`.
    ZZ, ///< A ZZ layer over the pairs in `zz`.
  };

  explicit Layer(Kind kind) : kind(kind) {}

  [[nodiscard]] bool empty() const { return sq.empty() && zz.empty(); }

  /// kind determines which of the two maps `sq` vs `zz` is non-empty (the other one must be empty).
  Kind kind;
  /// `SQ`: the rotation each ion receives.
  std::map<Ion, ZXZAngles> sq;
  /// `ZZ`: the angle of each coupled pair `(i, j)` with `i < j`.
  std::map<std::pair<Ion, Ion>, double> zz;
};

/// What the core hands to the emitter.
struct Schedule {
  SmallVector<Layer> layers;
  /// Diagonal rotations that never met a `zxz` on their ion; emitted as one `rz` per trap after the layers.
  std::map<Ion, double> residualRZ;
};

} // namespace

//===----------------------------------------------------------------------===//
// Core: gates -> layers
//===----------------------------------------------------------------------===//

/// Greedily schedules `gates` (in program order) into alternating layers.
///
/// Per ion the core tracks `last[i]`, the index of the latest layer with a gate on `i`, `lastSQ[i]`, the latest `SQ`
/// layer with a rotation on `i`, and `pending[i]`, an `rz` angle seen but not yet placed. Rules:
///
/// - `rz`: only accumulates in `pending`. Being diagonal it commutes with every ZZ layer, so it floats until the next
///   `zxz` on its ion absorbs it, or the end is reached.
/// - `zxz`: first absorbs `pending`. If the latest layer on `i` is an `SQ` layer the two rotations fuse (nothing
///   touches `i` in between); otherwise it goes into the first `SQ` layer after `last[i]`.
/// - `zz`: goes into the earliest ZZ layer after the latest layer on any of its ions, which is the latest ZZ layer such
///   that only diagonal gates touch the layer's ions between it and the gate. Angles of a pair already coupled in that
///   layer add up.
/// - At the end, every `pending` rotation is folded into `lastSQ[i]` if there is one (only diagonal gates on `i`
///   follow it, so it commutes back); the rest becomes `residualRZ`.
///
/// Measurements do not take part: `mzd` consumes its chain, so nothing follows it on its ions, and all of them go
/// after the last layer.
static Schedule layerGates(ArrayRef<Gate> gates) {
  Schedule schedule;
  SmallVector<Layer>& layers = schedule.layers;
  DenseMap<Ion, int64_t> last;
  DenseMap<Ion, int64_t> lastSQ;
  DenseMap<Ion, double> pending;

  auto lastLayer = [&](Ion ion) { return last.lookup_or(ion, -1); };

  auto isSQIndex = [](int64_t index) { return index % 2 == 0; };

  auto layerAt = [&](int64_t index) -> Layer& {
    while (std::cmp_less_equal(layers.size(), index)) {
      layers.emplace_back(isSQIndex(static_cast<int64_t>(layers.size())) ? Layer::Kind::SQ : Layer::Kind::ZZ);
    }
    return layers[static_cast<size_t>(index)];
  };

  auto takePending = [&](Ion ion) -> std::optional<double> {
    auto it = pending.find(ion);
    if (it == pending.end()) {
      return std::nullopt;
    }
    const double angle = it->second;
    pending.erase(it);
    return angle;
  };

  for (const Gate& gate : gates) {
    switch (gate.kind) {
    case Gate::Kind::RZ:
      pending[gate.ions.front()] += gate.angle;
      break;

    case Gate::Kind::ZXZ: {
      const Ion ion = gate.ions.front();
      ZXZAngles zxz = gate.zxz;
      if (std::optional<double> angle = takePending(ion)) {
        zxz = fuseZXZ(ZXZAngles{.z1 = *angle}, zxz);
      }

      int64_t index = lastLayer(ion);
      if (index >= 0 && isSQIndex(index)) {
        ZXZAngles& existing = layers[static_cast<size_t>(index)].sq.at(ion);
        existing = fuseZXZ(existing, zxz);
      } else {
        index += 1;
        layerAt(index).sq.emplace(ion, zxz);
      }
      last[ion] = index;
      lastSQ[ion] = index;
      break;
    }

    case Gate::Kind::ZZ: {
      const size_t n = gate.ions.size();
      auto at = [&](size_t i, size_t j) { return gate.matrix[(i * n) + j]; };

      // Only ions that are actually coupled take part; a zero row is no gate on that ion.
      SmallVector<Ion> coupled;
      int64_t latest = -1;
      for (size_t i = 0; i < n; ++i) {
        const bool isCoupled = llvm::any_of(llvm::seq<size_t>(0, n), [&](size_t j) { return at(i, j) != 0.0; });
        if (isCoupled) {
          coupled.push_back(gate.ions[i]);
          latest = std::max(latest, lastLayer(gate.ions[i]));
        }
      }
      if (coupled.empty()) {
        break;
      }

      // The latest ZZ layer touching a coupled ion, or the ZZ layer right after the latest SQ layer touching one
      // (layer 1 if no layer touches any of them yet).
      int64_t index = latest + 1;
      if (latest < 0) {
        index = 1;
      } else if (!isSQIndex(latest)) {
        index = latest;
      }
      Layer& layer = layerAt(index);
      for (size_t i = 0; i < n; ++i) {
        for (size_t j = i + 1; j < n; ++j) {
          if (at(i, j) != 0.0) {
            const auto key = std::minmax(gate.ions[i], gate.ions[j]);
            layer.zz[key] += at(i, j);
          }
        }
      }
      for (Ion ion : coupled) {
        last[ion] = index;
      }
      break;
    }
    }
  }

  for (const auto& [ion, angle] : pending) {
    auto it = lastSQ.find(ion);
    if (it == lastSQ.end()) {
      schedule.residualRZ[ion] = angle;
      continue;
    }
    ZXZAngles& existing = layers[static_cast<size_t>(it->second)].sq.at(ion);
    existing = fuseZXZ(existing, ZXZAngles{.z1 = angle});
  }

  return schedule;
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
struct Program {
  /// The one `magic.init` of the function, null if there is none.
  InitOp init;
  SmallVector<Gate> gates;
  /// The ops the gates were read from, in program order. The layers replace them.
  SmallVector<Operation*> gateOps;
  /// The measurements in program order. They move behind the layers.
  SmallVector<MZDOp> measurements;
};

} // namespace

/// Appends the gates `op` denotes to `gates`, one per ion for `zxz` / `rz`.
static void collectGates(Operation* op, SmallVectorImpl<Gate>& gates) {
  llvm::TypeSwitch<Operation*>(op)
      .Case([&](ZXZOp zxz) {
        for (auto [ion, z1, x, z2] :
             llvm::zip_equal(zxz.getIons(), toDoubles(zxz.getZ1()), toDoubles(zxz.getX()), toDoubles(zxz.getZ2()))) {
          gates.push_back(Gate{.kind = Gate::Kind::ZXZ, .ions = {ion}, .zxz = ZXZAngles{.z1 = z1, .x = x, .z2 = z2}});
        }
      })
      .Case([&](RZOp rz) {
        for (auto [ion, angle] : llvm::zip_equal(rz.getIons(), toDoubles(rz.getAngles()))) {
          gates.push_back(Gate{.kind = Gate::Kind::RZ, .ions = {ion}, .angle = angle});
        }
      })
      .Case([&](ActiveZZOp zz) {
        gates.push_back(Gate{
            .kind = Gate::Kind::ZZ,
            .ions = zz.getChainIn().getType().getActiveIons(),
            .matrix = llvm::to_vector(zz.getAngles().getValues<double>()),
        });
      })
      .Case([&](InterTrapZZOp zz) {
        const double angle = zz.getAngle().convertToDouble();
        gates.push_back(
            Gate{.kind = Gate::Kind::ZZ, .ions = llvm::to_vector(zz.getIons()), .matrix = {0.0, angle, angle, 0.0}});
      });
}

/// Whether `op` takes or yields an ion chain.
static bool touchesChains(Operation* op) {
  auto isChain = [](Type type) { return isa<IonChainType>(type); };
  return llvm::any_of(op->getOperandTypes(), isChain) || llvm::any_of(op->getResultTypes(), isChain);
}

/// Reads `block` into a `Program`, or fails with a diagnostic naming the pass `passName`.
static FailureOr<Program> analyzeBlock(Block& block, StringRef passName) {
  Program program;
  for (Operation& op : block) {
    const LogicalResult result =
        llvm::TypeSwitch<Operation*, LogicalResult>(&op)
            .Case([&](InitOp init) -> LogicalResult {
              if (program.init) {
                return init.emitOpError()
                       << "is the second 'magic.init' of the function, which " << passName << " does not support";
              }
              program.init = init;
              return success();
            })
            .Case<ZXZOp, RZOp, ActiveZZOp, InterTrapZZOp>([&](Operation* gate) {
              collectGates(gate, program.gates);
              program.gateOps.push_back(gate);
              return success();
            })
            .Case([&](MZDOp mzd) {
              program.measurements.push_back(mzd);
              return success();
            })
            .Default([&](Operation* other) -> LogicalResult {
              if (isa_and_present<MagicDialect>(other->getDialect())) {
                return other->emitOpError() << "is not supported by " << passName
                                            << ", which schedules zxz, rz, active_zz and inter_trap_zz only";
              }
              // Magic ops sit directly in the function, but a nested non-magic op may still use a chain.
              const WalkResult walk = other->walk([&](Operation* nested) {
                if (!touchesChains(nested)) {
                  return WalkResult::advance();
                }
                nested->emitOpError() << "is not a magic op but uses an ion chain, which " << passName
                                      << " does not support";
                return WalkResult::interrupt();
              });
              return failure(walk.wasInterrupted());
            });
    if (failed(result)) {
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

  void emitLayer(const Layer& layer) {
    if (layer.kind == Layer::Kind::SQ) {
      assert(layer.zz.empty() && "an SQ layer holds rotations only");
      emitRotations(layer.sq);
      return;
    }
    assert(layer.sq.empty() && "a ZZ layer holds couplings only");
    emitCouplings(layer.zz);
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
  /// One `zxz` per trap.
  void emitRotations(const std::map<Ion, ZXZAngles>& rotations) {
    for (auto& [trap, chain] : chains) {
      SmallVector<Ion> ions;
      SmallVector<double> z1;
      SmallVector<double> x;
      SmallVector<double> z2;
      for (const auto& [ion, rotation] : rotations) {
        if (trapOf.at(ion) == trap) {
          ions.push_back(ion);
          z1.push_back(rotation.z1);
          x.push_back(rotation.x);
          z2.push_back(rotation.z2);
        }
      }
      if (!ions.empty()) {
        chain = ZXZOp::create(builder, loc, chain, ions, z1, x, z2);
      }
    }
  }

  /// One `active_zz` per trap over its active ions, then one `inter_trap_zz` per coupling across traps. Pairs whose
  /// angles cancelled out are left out.
  void emitCouplings(const std::map<std::pair<Ion, Ion>, double>& couplings) {
    for (auto& [trap, chain] : chains) {
      const SmallVector<Ion> active = chain.getType().getActiveIons();
      const int64_t n = std::ssize(active);
      auto position = [&](Ion ion) { return llvm::find(active, ion) - active.begin(); };
      SmallVector<double> matrix(n * n, 0.0);
      bool nonzero = false;
      for (const auto& [pair, angle] : couplings) {
        if (angle == 0.0 || trapOf.at(pair.first) != trap || trapOf.at(pair.second) != trap) {
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

    for (const auto& [pair, angle] : couplings) {
      auto [ionA, ionB] = pair;
      int64_t trapA = trapOf.at(ionA);
      int64_t trapB = trapOf.at(ionB);
      if (angle == 0.0 || trapA == trapB) {
        continue;
      }
      // The lower trap first, so the output does not depend on the ion ids.
      if (trapA > trapB) {
        std::swap(ionA, ionB);
        std::swap(trapA, trapB);
      }
      TypedValue<IonChainType>& chainA = chains.at(trapA);
      TypedValue<IonChainType>& chainB = chains.at(trapB);
      auto zz = InterTrapZZOp::create(builder, loc, chainA.getType(), chainB.getType(), chainA, chainB,
                                      builder.getDenseI64ArrayAttr({ionA, ionB}), builder.getF64FloatAttr(angle));
      chainA = zz.getAOut();
      chainB = zz.getBOut();
    }
  }

  OpBuilder builder;
  Location loc;
  /// The current chain value per trap, by trap id.
  std::map<int64_t, TypedValue<IonChainType>> chains;
  /// The trap of every ion.
  DenseMap<Ion, int64_t> trapOf;
};

} // namespace

/// Replaces the gates of `program` by the layers of `schedule` and moves the measurements behind them. Everything else
/// stays where it is.
static void rebuild(const Program& program, const Schedule& schedule, Location loc) {
  LayerEmitter emitter(program.init, loc);
  for (const Layer& layer : schedule.layers) {
    if (!layer.empty()) {
      emitter.emitLayer(layer);
    }
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
    if (program->init == nullptr) {
      return; // Nothing quantum to schedule here.
    }
    rebuild(*program, layerGates(program->gates), func.getLoc());
  }
};

} // namespace
} // namespace qcc::magic
