// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// `qvec-layer` in two halves: a pure core that turns a list of gates over static qubits into a list of layers, and an
// analysis / builder pair around it that reads the gates off a function and emits a fresh body. Nothing is moved in
// place.
//
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVec.h"
#include "qcc/Dialect/QVec/Transforms/Angles.h"
#include "qcc/Dialect/QVec/Transforms/Passes.h" // IWYU pragma: keep
#include "qcc/Dialect/QVec/Transforms/ZXZ.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/QCO/IR/QCOOps.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h"

#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <map>
#include <optional>
#include <utility>

using namespace mlir;
using namespace qcc::qvec;

//===----------------------------------------------------------------------===//
// Gate model
//===----------------------------------------------------------------------===//

namespace {

/// A static qubit, identified by the index of its `qco.static`.
using Qubit = int64_t;

/// One gate of the input program on static qubits, in the gate set the pass understands.
struct Gate {
  enum class Kind : uint8_t {
    ZXZ, ///< `single u_zxz` on one lane: `qubits[0]`, `zxz`.
    Rz,  ///< `single rz` on one lane: `qubits[0]`, `angle`.
    Zz,  ///< `pair rzz` on one lane or `global zz`: the row-major `matrix` over `qubits`.
    Mz,  ///< `mz`: measures `qubits` (lane order), `op` is the `qvec.mz` whose bits the rebuild has to replace.
  };

  Kind kind;
  SmallVector<Qubit> qubits;
  ZXZAngles zxz;
  double angle = 0.0;
  SmallVector<double> matrix;
  Operation* op = nullptr;
};

/// One layer of the schedule. Layers strictly alternate between the two kinds, starting with `Sq` (which may be
/// empty if the program opens with a coupling).
struct Layer {
  enum class Kind : uint8_t {
    Sq, ///< A `single u_zxz` over the qubits in `rotations`.
    Zz, ///< A `global zz` over the qubits appearing in `couplings`.
  };

  explicit Layer(Kind kind) : kind(kind) {}

  [[nodiscard]] bool empty() const { return rotations.empty() && couplings.empty(); }

  Kind kind;
  /// `Sq`: the rotation each qubit receives. Ordered so that the emitted lanes are ordered by qubit.
  std::map<Qubit, ZXZAngles> rotations;
  /// `Zz`: the angle of each coupled pair `(i, j)` with `i < j`.
  std::map<std::pair<Qubit, Qubit>, double> couplings;
};

/// What the core hands to the builder.
struct Schedule {
  SmallVector<Layer> layers;
  /// Diagonal rotations that never met a `u_zxz` on their qubit; emitted as one `single rz` after the layers.
  std::map<Qubit, double> residualRz;
};

} // namespace

//===----------------------------------------------------------------------===//
// Core: gates -> layers
//===----------------------------------------------------------------------===//

/// Greedily schedules `gates` (in program order) into alternating layers.
///
/// Per qubit the core tracks `last[q]`, the index of the latest layer with a gate on `q`, `lastSq[q]`, the latest
/// `Sq` layer with a rotation on `q`, and `pending[q]`, an `rz` angle seen but not yet placed. Rules:
///
/// - `rz`: only accumulates in `pending`. Being diagonal it commutes with every ZZ block, so it floats until the next
///   `u_zxz` on its qubit absorbs it, or the end is reached.
/// - `u_zxz`: first absorbs `pending`. If the latest layer on `q` is an `Sq` layer the two rotations fuse (nothing
///   touches `q` in between); otherwise it goes into the first `Sq` layer after `last[q]`.
/// - `zz`: goes into the earliest ZZ layer after the latest layer on any of its qubits, which is the latest ZZ block
///   such that only diagonal gates touch the block's qubits between it and the gate. Angles of a pair already coupled
///   in that block add up.
/// - At the end, every `pending` rotation is folded into `lastSq[q]` if there is one (only diagonal gates on `q`
///   follow it, so it commutes back); the rest becomes `residualRz`.
///
/// Measurements do not take part: the analysis guarantees that nothing follows a measurement on its qubit, so all of
/// them go after the last layer.
static Schedule layerGates(ArrayRef<Gate> gates) {
  Schedule schedule;
  SmallVector<Layer>& layers = schedule.layers;
  DenseMap<Qubit, int64_t> last;
  DenseMap<Qubit, int64_t> lastSq;
  DenseMap<Qubit, double> pending;

  auto lastLayer = [&](Qubit qubit) { return last.lookup_or(qubit, -1); };
  auto isSqIndex = [](int64_t index) { return index % 2 == 0; };
  auto layerAt = [&](int64_t index) -> Layer& {
    while (std::cmp_less_equal(layers.size(), index)) {
      layers.emplace_back(isSqIndex(static_cast<int64_t>(layers.size())) ? Layer::Kind::Sq : Layer::Kind::Zz);
    }
    return layers[static_cast<size_t>(index)];
  };
  auto takePending = [&](Qubit qubit) -> std::optional<double> {
    auto it = pending.find(qubit);
    if (it == pending.end()) {
      return std::nullopt;
    }
    const double angle = it->second;
    pending.erase(it);
    return angle;
  };

  for (const Gate& gate : gates) {
    switch (gate.kind) {
    case Gate::Kind::Rz:
      pending[gate.qubits.front()] += gate.angle;
      break;

    case Gate::Kind::ZXZ: {
      const Qubit qubit = gate.qubits.front();
      ZXZAngles rotation = gate.zxz;
      if (std::optional<double> angle = takePending(qubit)) {
        rotation = fuseZXZ(ZXZAngles{.z1 = *angle}, rotation);
      }

      int64_t index = lastLayer(qubit);
      if (index >= 0 && isSqIndex(index)) {
        ZXZAngles& existing = layers[static_cast<size_t>(index)].rotations.at(qubit);
        existing = fuseZXZ(existing, rotation);
      } else {
        index += 1;
        layerAt(index).rotations.emplace(qubit, rotation);
      }
      last[qubit] = index;
      lastSq[qubit] = index;
      break;
    }

    case Gate::Kind::Zz: {
      const size_t n = gate.qubits.size();
      auto at = [&](size_t i, size_t j) { return gate.matrix[(i * n) + j]; };

      // Only qubits that are actually coupled take part; a zero row is no gate on that qubit.
      SmallVector<Qubit> coupled;
      int64_t latest = -1;
      for (size_t i = 0; i < n; ++i) {
        const bool isCoupled = llvm::any_of(llvm::seq<size_t>(0, n), [&](size_t j) { return at(i, j) != 0.0; });
        if (isCoupled) {
          coupled.push_back(gate.qubits[i]);
          latest = std::max(latest, lastLayer(gate.qubits[i]));
        }
      }
      if (coupled.empty()) {
        break;
      }

      // The latest ZZ layer touching a coupled qubit, or the ZZ layer right after the latest SQ layer touching one
      // (layer 1 if no layer touches any of them yet).
      int64_t index = latest + 1;
      if (latest < 0) {
        index = 1;
      } else if (!isSqIndex(latest)) {
        index = latest;
      }
      Layer& layer = layerAt(index);
      for (size_t i = 0; i < n; ++i) {
        for (size_t j = i + 1; j < n; ++j) {
          if (at(i, j) != 0.0) {
            const auto key = std::minmax(gate.qubits[i], gate.qubits[j]);
            layer.couplings[key] += at(i, j);
          }
        }
      }
      for (Qubit qubit : coupled) {
        last[qubit] = index;
      }
      break;
    }

    case Gate::Kind::Mz:
      break;
    }
  }

  for (const auto& [qubit, angle] : pending) {
    auto it = lastSq.find(qubit);
    if (it == lastSq.end()) {
      schedule.residualRz[qubit] = angle;
      continue;
    }
    ZXZAngles& existing = layers[static_cast<size_t>(it->second)].rotations.at(qubit);
    existing = fuseZXZ(existing, ZXZAngles{.z1 = angle});
  }

  return schedule;
}

//===----------------------------------------------------------------------===//
// Analysis: function -> gates
//===----------------------------------------------------------------------===//

/// Whether `type` carries qubits, one or a whole vector of them.
static bool carriesQubits(Type type) {
  auto shapedType = dyn_cast<ShapedType>(type);
  return isa<qco::QubitType>(shapedType ? shapedType.getElementType() : type);
}

/// Whether `op` only moves qubits around between vectors. The rebuild regenerates all of that.
static bool isQubitPlumbing(Operation* op) {
  return isa<qco::StaticOp, vector::FromElementsOp, vector::ExtractOp, vector::ExtractStridedSliceOp,
             vector::BroadcastOp>(op) &&
         llvm::any_of(op->getResultTypes(), carriesQubits);
}

namespace {

/// Everything the builder needs besides the schedule.
struct Program {
  SmallVector<Gate> gates;
  /// The classical operations (including the terminator) in program order; cloned behind the measurements.
  SmallVector<Operation*> tail;
  /// All qubits the program touches, ascending.
  SmallVector<Qubit> qubits;
};

} // namespace

/// Resolves every lane of `qubits` to its static qubit, or fails with a diagnostic at `op`.
static LogicalResult resolveQubits(Operation* op, TypedValue<VectorType> qubits, SmallVectorImpl<Qubit>& result) {
  for (int64_t lane = 0, width = qubits.getType().getNumElements(); lane < width; ++lane) {
    qco::StaticOp staticOp = getStaticOpAncestor(qubits, lane);
    if (!staticOp) {
      return op->emitOpError() << "lane " << lane << " cannot be traced back to a `qco.static` qubit";
    }
    result.push_back(static_cast<Qubit>(staticOp.getIndex()));
  }
  return success();
}

/// Reads the constant angles of `angles`, or fails with a diagnostic at `op`.
static FailureOr<SmallVector<double>> resolveAngles(Operation* op, Value angles) {
  std::optional<SmallVector<double>> values = getConstantAngles(angles);
  if (!values) {
    return op->emitOpError() << "angles must be compile-time constants";
  }
  return *values;
}

/// Appends the gates `op` denotes to `gates`, one per lane for `single` / `pair`.
static LogicalResult collectGates(QubitLaneOpInterface op, SmallVectorImpl<Gate>& gates) {
  return TypeSwitch<Operation*, LogicalResult>(op)
      .Case([&](SingleOp singleOp) -> LogicalResult {
        SmallVector<Qubit> qubits;
        if (failed(resolveQubits(singleOp, singleOp.getQubitsIn(), qubits))) {
          return failure();
        }
        switch (singleOp.getGateKind()) {
        case SingleGateKind::RZ: {
          FailureOr<SmallVector<double>> theta = resolveAngles(singleOp, singleOp.getParams().front());
          if (failed(theta)) {
            return failure();
          }
          for (auto [qubit, angle] : llvm::zip_equal(qubits, *theta)) {
            gates.push_back(Gate{.kind = Gate::Kind::Rz, .qubits = {qubit}, .angle = angle, .op = singleOp});
          }
          return success();
        }
        case SingleGateKind::UZXZ: {
          FailureOr<SmallVector<double>> z1 = resolveAngles(singleOp, singleOp.getParams()[zxz::z1]);
          FailureOr<SmallVector<double>> x = resolveAngles(singleOp, singleOp.getParams()[zxz::x]);
          FailureOr<SmallVector<double>> z2 = resolveAngles(singleOp, singleOp.getParams()[zxz::z2]);
          if (failed(z1) || failed(x) || failed(z2)) {
            return failure();
          }
          for (auto [qubit, a, b, c] : llvm::zip_equal(qubits, *z1, *x, *z2)) {
            gates.push_back(Gate{
                .kind = Gate::Kind::ZXZ,
                .qubits = {qubit},
                .zxz = ZXZAngles{.z1 = a, .x = b, .z2 = c},
                .op = singleOp,
            });
          }
          return success();
        }
        default:
          return singleOp.emitOpError() << "gate '" << stringifySingleGateKind(singleOp.getGateKind())
                                        << "' is not in the layered gate set (rz, u_zxz); run qvec-to-u-zxz first";
        }
      })
      .Case([&](PairOp pairOp) -> LogicalResult {
        if (pairOp.getGateKind() != PairGateKind::RZZ) {
          return pairOp.emitOpError() << "gate '" << stringifyPairGateKind(pairOp.getGateKind())
                                      << "' is not in the layered gate set (rzz); run qvec-to-rzz first";
        }
        SmallVector<Qubit> lhs;
        SmallVector<Qubit> rhs;
        if (failed(resolveQubits(pairOp, pairOp.getLhsIn(), lhs)) ||
            failed(resolveQubits(pairOp, pairOp.getRhsIn(), rhs))) {
          return failure();
        }
        FailureOr<SmallVector<double>> theta = resolveAngles(pairOp, pairOp.getParams().front());
        if (failed(theta)) {
          return failure();
        }
        for (auto [a, b, angle] : llvm::zip_equal(lhs, rhs, *theta)) {
          gates.push_back(
              Gate{.kind = Gate::Kind::Zz, .qubits = {a, b}, .matrix = {0.0, angle, angle, 0.0}, .op = pairOp});
        }
        return success();
      })
      .Case([&](GlobalOp globalOp) -> LogicalResult {
        SmallVector<Qubit> qubits;
        if (failed(resolveQubits(globalOp, globalOp.getQubitsIn(), qubits))) {
          return failure();
        }
        FailureOr<SmallVector<double>> matrix = resolveAngles(globalOp, globalOp.getAngles());
        if (failed(matrix)) {
          return failure();
        }
        gates.push_back(Gate{.kind = Gate::Kind::Zz, .qubits = qubits, .matrix = *matrix, .op = globalOp});
        return success();
      })
      .Case([&](MZOp mzOp) -> LogicalResult {
        SmallVector<Qubit> qubits;
        if (failed(resolveQubits(mzOp, mzOp.getQubitsIn(), qubits))) {
          return failure();
        }
        gates.push_back(Gate{.kind = Gate::Kind::Mz, .qubits = qubits, .op = mzOp});
        return success();
      })
      .Default([](Operation* other) { return other->emitOpError() << "is not supported by qvec-layer"; });
}

/// Reads `func` into a `Program`, or fails with a diagnostic.
static FailureOr<Program> analyzeFunction(func::FuncOp func) {
  if (!func.getBody().hasOneBlock()) {
    return func.emitOpError() << "qvec-layer expects a single-block function";
  }
  Block& block = func.getBody().front();
  if (llvm::any_of(block.getArgumentTypes(), carriesQubits)) {
    return func.emitOpError() << "qvec-layer expects qubits to come from `qco.static`, not from arguments";
  }

  Program program;
  for (Operation& op : block) {
    if (auto laneOp = dyn_cast<QubitLaneOpInterface>(&op)) {
      if (failed(collectGates(laneOp, program.gates))) {
        return failure();
      }
      continue;
    }
    if (isQubitPlumbing(&op)) {
      continue;
    }
    if (op.getNumRegions() != 0) {
      return op.emitOpError() << "qvec-layer does not support control flow";
    }
    if (llvm::any_of(op.getOperandTypes(), carriesQubits) || llvm::any_of(op.getResultTypes(), carriesQubits)) {
      return op.emitOpError() << "is not a `qvec` operation and qvec-layer cannot look through it";
    }
    program.tail.push_back(&op);
  }

  // The tail is cloned behind the gates, so it may only depend on arguments, on itself and on measurement results.
  const DenseSet<Operation*> tail(program.tail.begin(), program.tail.end());
  for (Operation* op : program.tail) {
    for (Value operand : op->getOperands()) {
      Operation* producer = operand.getDefiningOp();
      if (producer != nullptr && !tail.contains(producer) && !isa<MZOp>(producer)) {
        return op->emitOpError() << "depends on a value that qvec-layer does not preserve";
      }
    }
  }

  // A qubit is at most measured once and never used afterwards; each gate acts on distinct qubits.
  DenseSet<Qubit> measured;
  DenseSet<Qubit> seen;
  for (const Gate& gate : program.gates) {
    DenseSet<Qubit> own;
    for (Qubit qubit : gate.qubits) {
      if (!own.insert(qubit).second) {
        return gate.op->emitOpError() << "acts twice on qubit " << qubit;
      }
      if (measured.contains(qubit)) {
        return gate.op->emitOpError() << "uses qubit " << qubit << " after its measurement";
      }
      seen.insert(qubit);
    }
    if (gate.kind == Gate::Kind::Mz) {
      measured.insert_range(gate.qubits);
    }
  }

  program.qubits = llvm::to_vector(seen);
  llvm::sort(program.qubits);
  return program;
}

//===----------------------------------------------------------------------===//
// Builder: schedule -> fresh function body
//===----------------------------------------------------------------------===//

namespace {

/// Emits the rebuilt body. Every qubit lives in a scalar `!qco.qubit` value between layers; a layer gathers its
/// lanes with `vector.from_elements` and scatters the result back with `vector.extract`, which keeps the provenance
/// traceable for everything downstream.
class BodyBuilder {
public:
  BodyBuilder(const OpBuilder& builder, Location loc) : builder(builder), loc(loc) {}

  void declareQubits(ArrayRef<Qubit> qubits) {
    for (Qubit qubit : qubits) {
      current[qubit] =
          qco::StaticOp::create(builder, loc, qco::QubitType::get(builder.getContext()), static_cast<uint64_t>(qubit));
    }
  }

  void emitLayer(const Layer& layer) {
    if (layer.kind == Layer::Kind::Sq) {
      SmallVector<Qubit> qubits;
      SmallVector<double> z1;
      SmallVector<double> x;
      SmallVector<double> z2;
      for (const auto& [qubit, rotation] : layer.rotations) {
        qubits.push_back(qubit);
        z1.push_back(rotation.z1);
        x.push_back(rotation.x);
        z2.push_back(rotation.z2);
      }
      Value qs = gather(qubits);
      auto op = SingleOp::create(builder, loc, SingleGateKind::UZXZ, qs,
                                 ValueRange{
                                     buildAngleVector(builder, loc, z1),
                                     buildAngleVector(builder, loc, x),
                                     buildAngleVector(builder, loc, z2),
                                 });
      scatter(op.getQubitsOut(), qubits);
      return;
    }

    SmallVector<Qubit> qubits;
    for (const auto& [pair, angle] : layer.couplings) {
      qubits.push_back(pair.first);
      qubits.push_back(pair.second);
    }
    llvm::sort(qubits);
    qubits.erase(llvm::unique(qubits), qubits.end());

    const size_t n = qubits.size();
    SmallVector<double> matrix(n * n, 0.0);
    auto position = [&](Qubit qubit) { return static_cast<size_t>(llvm::lower_bound(qubits, qubit) - qubits.begin()); };
    for (const auto& [pair, angle] : layer.couplings) {
      const size_t i = position(pair.first);
      const size_t j = position(pair.second);
      matrix[(i * n) + j] = angle;
      matrix[(j * n) + i] = angle;
    }
    Value qs = gather(qubits);
    auto op = GlobalOp::create(builder, loc, GlobalGateKind::ZZ, qs,
                               buildAngleMatrix(builder, loc, static_cast<int64_t>(n), matrix));
    scatter(op.getQubitsOut(), qubits);
  }

  void emitResidualRz(const std::map<Qubit, double>& residual) {
    if (residual.empty()) {
      return;
    }
    SmallVector<Qubit> qubits;
    SmallVector<double> theta;
    for (const auto& [qubit, angle] : residual) {
      qubits.push_back(qubit);
      theta.push_back(normalizeAngle(angle));
    }
    Value qs = gather(qubits);
    auto op = SingleOp::create(builder, loc, SingleGateKind::RZ, qs, ValueRange{buildAngleVector(builder, loc, theta)});
    scatter(op.getQubitsOut(), qubits);
  }

  /// Measures `gate.qubits` and maps the bits of the original `mz` to the new ones in `mapping`.
  void emitMeasurement(const Gate& gate, IRMapping& mapping) {
    auto mzOp = cast<MZOp>(gate.op);
    Value qs = gather(gate.qubits);
    auto bitsType = VectorType::get({static_cast<int64_t>(gate.qubits.size())}, builder.getI1Type());
    auto op = MZOp::create(builder, mzOp.getLoc(), qs.getType(), bitsType, qs);
    mapping.map(mzOp.getBits(), op.getBits());
    for (Qubit qubit : gate.qubits) {
      current.erase(qubit); // Measured: nothing may use it anymore (the analysis checked).
    }
  }

private:
  Value gather(ArrayRef<Qubit> qubits) {
    SmallVector<Value> elements;
    for (Qubit qubit : qubits) {
      assert(current.contains(qubit) && "qubit is not live");
      elements.push_back(current[qubit]);
    }
    auto vectorType = VectorType::get({static_cast<int64_t>(elements.size())}, elements.front().getType());
    return vector::FromElementsOp::create(builder, loc, vectorType, elements);
  }

  void scatter(Value vector, ArrayRef<Qubit> qubits) {
    for (auto [lane, qubit] : llvm::enumerate(qubits)) {
      current[qubit] = vector::ExtractOp::create(builder, loc, vector, static_cast<int64_t>(lane));
    }
  }

  OpBuilder builder; // A copy of the caller's builder; both append to the end of the same block.
  Location loc;
  DenseMap<Qubit, Value> current;
};

} // namespace

/// Replaces the body of `func` by the rebuilt one.
static void rebuildFunction(func::FuncOp func, const Program& program, const Schedule& schedule) {
  Region& region = func.getBody();
  Block& oldBlock = region.front();
  OpBuilder builder(func.getContext());

  SmallVector<Location> argLocs =
      llvm::map_to_vector(oldBlock.getArguments(), [](BlockArgument arg) { return arg.getLoc(); });
  Block* newBlock = builder.createBlock(&region, region.end(), oldBlock.getArgumentTypes(), argLocs);
  IRMapping mapping;
  mapping.map(oldBlock.getArguments(), newBlock->getArguments());

  BodyBuilder body(builder, func.getLoc());
  body.declareQubits(program.qubits);
  for (const Layer& layer : schedule.layers) {
    if (!layer.empty()) {
      body.emitLayer(layer);
    }
  }
  body.emitResidualRz(schedule.residualRz);
  for (const Gate& gate : program.gates) {
    if (gate.kind == Gate::Kind::Mz) {
      body.emitMeasurement(gate, mapping);
    }
  }
  for (Operation* op : program.tail) {
    builder.clone(*op, mapping);
  }

  oldBlock.erase();

  // Constants that only fed the old gates are dead now.
  for (Operation& op : llvm::make_early_inc_range(llvm::reverse(*newBlock))) {
    if (isOpTriviallyDead(&op)) {
      op.erase();
    }
  }
}

//===----------------------------------------------------------------------===//
// Pass
//===----------------------------------------------------------------------===//

namespace qcc {

#define GEN_PASS_DEF_QVECLAYER
#include "qcc/Dialect/QVec/Transforms/Passes.h.inc"

namespace {

struct QVecLayer final : impl::QVecLayerBase<QVecLayer> {
  using QVecLayerBase::QVecLayerBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();
    for (func::FuncOp func : llvm::make_early_inc_range(moduleOp.getOps<func::FuncOp>())) {
      if (func.isExternal() || func.getBody().getOps<QubitLaneOpInterface>().empty()) {
        continue; // Nothing quantum to schedule here.
      }
      FailureOr<Program> program = analyzeFunction(func);
      if (failed(program)) {
        return signalPassFailure();
      }
      const Schedule schedule = layerGates(program->gates);
      rebuildFunction(func, *program, schedule);
    }
  }
};

} // namespace
} // namespace qcc
