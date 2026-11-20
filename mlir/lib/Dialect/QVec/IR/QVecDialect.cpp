// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QCF/IR/QCF.h"
#include "qcc/Dialect/QVec/IR/QVec.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpImplementation.h" // IWYU pragma: keep
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cassert>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <utility>

using namespace mlir;
using namespace qcc::qvec;

#include "qcc/Dialect/QVec/IR/QVecDialect.cpp.inc"

#define GET_OP_CLASSES
#include "qcc/Dialect/QVec/IR/QVecOps.cpp.inc"

//===----------------------------------------------------------------------===//
// Verifiers
//===----------------------------------------------------------------------===//

/// Verifies that the angle vectors `params` of a gate are lane-aligned with its qubit vector of type `qubitsType`.
static LogicalResult verifyParamShapes(Operation* op, VectorType qubitsType, OperandRange params) {
  for (Value param : params) {
    auto paramType = cast<VectorType>(param.getType());
    if (paramType.getShape() != qubitsType.getShape()) {
      return op->emitOpError() << "parameter type " << paramType << " does not match the shape of the qubit vector "
                               << qubitsType;
    }
  }
  return success();
}

LogicalResult SingleOp::verify() {
  if (failed(qcc::detail::verifyGateParams(*this, getGateKind(), getParams()))) {
    return failure();
  }
  return verifyParamShapes(*this, getQubitsIn().getType(), getParams());
}

LogicalResult PairOp::verify() {
  if (failed(qcc::detail::verifyGateParams(*this, getGateKind(), getParams()))) {
    return failure();
  }
  return verifyParamShapes(*this, getLhsIn().getType(), getParams());
}

//===----------------------------------------------------------------------===//
// Dialect
//===----------------------------------------------------------------------===//

void QVecDialect::initialize() {
  addTypes<>();

  addOperations<
#define GET_OP_LIST
#include "qcc/Dialect/QVec/IR/QVecOps.cpp.inc"
      >();
}

//===----------------------------------------------------------------------===//
// Qubit provenance
//===----------------------------------------------------------------------===//

namespace {

/// Represents a single qubit.
///
/// There are two cases:
/// 1. A qubit in a vector.
/// 2. A standalone qubit (not part of a vector).
///
/// In the first case `value` refers to a vector of qubits and `index` points to the qubit we mean. In the second case
/// `value` is already the qubit itself and `index` has no meaning (nullopt).
struct QubitRef {
  [[nodiscard]] bool isInVector() const { return index.has_value(); }

  Value value;
  std::optional<int64_t> index;
};

/// The result of tracing a qubit one step back towards its definition.
class QubitStep {
public:
  enum class Kind : uint8_t {
    Stepped, ///< The same qubit, one step closer to its definition.
    Origin,  ///< The trail ends here, because nothing upstream of the definition holds this qubit.
    Unknown, ///< An operation this walk cannot look through, so the origin stays out of reach.
  };

  /// Constructs a terminal step (`Origin` or `Unknown`): the walk stops here, so there is no qubit to continue with.
  explicit QubitStep(Kind kind) : kind(kind) {
    assert(kind != Kind::Stepped && "Stepped requires a qubit; use the other constructor");
  }

  /// Constructs a `Stepped` result: `qubit` is where the walk continues next.
  explicit QubitStep(QubitRef qubit) : kind(Kind::Stepped), qubit(qubit) {}

  [[nodiscard]] Kind getKind() const { return kind; }

  /// Where to continue. Only valid for `Stepped`.
  [[nodiscard]] QubitRef getQubit() const {
    assert(kind == Kind::Stepped && "qubit is only defined for Stepped");
    return qubit;
  }

private:
  Kind kind;
  QubitRef qubit;
};

} // namespace

/// Convenience wrapper to `QubitStep` ctor for stepped kind.
static QubitStep stepTo(Value value, std::optional<int64_t> index = std::nullopt) {
  return QubitStep(QubitRef{.value = value, .index = index});
}

/// Whether `type` carries qubits, one or a whole vector of them.
static bool carriesQubits(Type type) {
  auto shapedType = dyn_cast<ShapedType>(type);
  return isa<qcc::QubitType>(shapedType ? shapedType.getElementType() : type);
}

/// Traces the qubit `argument` holds (element `index` if it is a vector) one step back. A binding of `qcf.if` is the
/// qubit it binds, element by element. Any other block argument is an origin.
static QubitStep stepBackArgument(BlockArgument argument, std::optional<int64_t> index) {
  auto ifOp = dyn_cast_if_present<qcc::qcf::IfOp>(argument.getOwner()->getParentOp());
  if (!ifOp) {
    return QubitStep(QubitStep::Kind::Origin);
  }
  return stepTo(ifOp.getQubitsIn()[argument.getArgNumber()], index);
}

/// Traces the scalar qubit `element`, defined by `definingOp`, one step back.
static QubitStep stepBackElement(Operation* definingOp) {
  // The element may be read out of another qubit vector, in which case the walk continues there.
  if (auto extractOp = dyn_cast<vector::ExtractOp>(definingOp)) {
    if (extractOp.hasDynamicPosition() || extractOp.getStaticPosition().size() != 1) {
      return QubitStep(QubitStep::Kind::Unknown);
    }
    return stepTo(extractOp.getSource(), extractOp.getStaticPosition().front());
  }

  // An operation without qubit inputs creates the qubits it returns, `qcc.static` being the one we care about.
  // Anything else may well pass a qubit through, and we cannot tell from where.
  if (llvm::none_of(definingOp->getOperandTypes(), carriesQubits)) {
    return QubitStep(QubitStep::Kind::Origin);
  }
  return QubitStep(QubitStep::Kind::Unknown);
}

/// Traces element `index` of the qubit vector defined by `definingOp` one step back.
static QubitStep stepBackVectorElement(Operation* definingOp, int64_t index) {
  if (auto fromElementsOp = dyn_cast<vector::FromElementsOp>(definingOp)) {
    ValueRange elements = fromElementsOp.getElements();
    assert(index >= 0 && std::cmp_less(index, elements.size()) && "index out of bounds");
    return stepTo(elements[static_cast<size_t>(index)]);
  }

  if (auto sliceOp = dyn_cast<vector::ExtractStridedSliceOp>(definingOp)) {
    if (sliceOp.getSourceVectorType().getRank() != 1 || sliceOp.getOffsets().size() != 1 ||
        sliceOp.hasNonUnitStrides()) {
      return QubitStep(QubitStep::Kind::Unknown);
    }
    SmallVector<int64_t> offsets;
    sliceOp.getOffsets(offsets);
    return stepTo(sliceOp.getSource(), offsets.front() + index);
  }

  if (auto broadcastOp = dyn_cast<vector::BroadcastOp>(definingOp)) {
    // A qubit vector holds distinct qubits, so only the "trivial" broadcast to a single-element vector makes sense.
    if (broadcastOp.getResultVectorType().getNumElements() != 1 || index != 0 ||
        isa<VectorType>(broadcastOp.getSourceType())) {
      return QubitStep(QubitStep::Kind::Unknown);
    }
    return stepTo(broadcastOp.getSource());
  }

  return QubitStep(QubitStep::Kind::Unknown);
}

/// Traces `qubit` one step back towards its definition, through the operations that only move qubits around.
static QubitStep stepBack(QubitRef qubit) {
  if (auto argument = dyn_cast<BlockArgument>(qubit.value)) {
    return stepBackArgument(argument, qubit.index);
  }

  // A lane op, e.g. a `qvec` op or `qcf.if`, hands its qubits on lane by lane, element order untouched, so the index
  // carries over.
  auto result = cast<OpResult>(qubit.value);
  if (auto laneOp = dyn_cast<qcc::QubitLaneOpInterface>(result.getOwner())) {
    return stepTo(laneOp.getTiedQubitOperand(result), qubit.index);
  }

  return qubit.isInVector() ? stepBackVectorElement(result.getOwner(), *qubit.index)
                            : stepBackElement(result.getOwner());
}

std::optional<int64_t> qcc::qvec::getStaticQubitIndex(TypedValue<VectorType> qubits, int64_t index) {
  assert(index >= 0 && index < qubits.getType().getNumElements() && "index out of bounds for qubits");

  // Every step moves strictly towards a definition, so the walk terminates.
  for (QubitRef qubit{.value = qubits, .index = index};;) {
    const QubitStep step = stepBack(qubit);
    if (step.getKind() == QubitStep::Kind::Unknown) {
      return std::nullopt;
    }
    if (step.getKind() == QubitStep::Kind::Origin) {
      // A vector value is never defined by a `qcc.static`, so this covers both ends of the walk.
      auto staticOp = qubit.value.getDefiningOp<qcc::StaticOp>();
      if (!staticOp) {
        return std::nullopt;
      }
      return staticOp.getIndices()[cast<OpResult>(qubit.value).getResultNumber()];
    }
    assert(step.getKind() == QubitStep::Kind::Stepped && "unexpected QubitStep::Kind");
    qubit = step.getQubit();
  }
}
