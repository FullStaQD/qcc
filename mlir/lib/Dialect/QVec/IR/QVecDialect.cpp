// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVec.h"

#include "mlir/Dialect/QCO/IR/QCOOps.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectImplementation.h" // IWYU pragma: keep
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h" // IWYU pragma: keep

#include <cassert>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <utility>

using namespace mlir;
using namespace qcc::qvec;

#include "qcc/Dialect/QVec/IR/QVecDialect.cpp.inc"
#include "qcc/Dialect/QVec/IR/QVecEnums.cpp.inc"
#include "qcc/Dialect/QVec/IR/QVecInterfaces.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/QVec/IR/QVecAttrs.cpp.inc"

#define GET_OP_CLASSES
#include "qcc/Dialect/QVec/IR/QVecOps.cpp.inc"

void QVecDialect::initialize() {
  addTypes<>();

  addAttributes<
#define GET_ATTRDEF_LIST
#include "qcc/Dialect/QVec/IR/QVecAttrs.cpp.inc"
      >();

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
  return isa<qco::QubitType>(shapedType ? shapedType.getElementType() : type);
}

/// Traces the scalar qubit `element` one step back.
static QubitStep stepBackElement(Value element) {
  Operation* definingOp = element.getDefiningOp();
  if (definingOp == nullptr) {
    return QubitStep(QubitStep::Kind::Origin); // A block argument.
  }

  // The element may be read out of another qubit vector, in which case the walk continues there.
  if (auto extractOp = dyn_cast<vector::ExtractOp>(definingOp)) {
    if (extractOp.hasDynamicPosition() || extractOp.getStaticPosition().size() != 1) {
      return QubitStep(QubitStep::Kind::Unknown);
    }
    return stepTo(extractOp.getSource(), extractOp.getStaticPosition().front());
  }

  // An operation without qubit inputs creates the qubits it returns, `qco.static` and `qco.alloc` being the ones we
  // care about. Anything else may well pass a qubit through, and we cannot tell from where.
  if (llvm::none_of(definingOp->getOperandTypes(), carriesQubits)) {
    return QubitStep(QubitStep::Kind::Origin);
  }
  return QubitStep(QubitStep::Kind::Unknown);
}

/// Traces element `index` of the qubit vector `qubits` one step back.
static QubitStep stepBackVectorElement(Value qubits, int64_t index) {
  Operation* definingOp = qubits.getDefiningOp();
  if (definingOp == nullptr) {
    return QubitStep(QubitStep::Kind::Origin); // A block argument.
  }

  // A `qvec` operation hands its qubits on slot by slot, element order untouched, so the index carries over.
  if (auto slotOp = dyn_cast<QubitSlotOpInterface>(definingOp)) {
    Value tied = slotOp.getTiedQubitOperand(cast<OpResult>(qubits));
    return tied ? stepTo(tied, index) : QubitStep(QubitStep::Kind::Origin);
  }

  if (auto fromElementsOp = dyn_cast<vector::FromElementsOp>(definingOp)) {
    ValueRange elements = fromElementsOp.getElements();
    if (index < 0 || std::cmp_greater_equal(index, elements.size())) {
      return QubitStep(QubitStep::Kind::Unknown); // FIXME: how is this possible?
    }
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
  return qubit.isInVector() ? stepBackVectorElement(qubit.value, *qubit.index) : stepBackElement(qubit.value);
}

qco::StaticOp qcc::qvec::getStaticOpAncestor(TypedValue<VectorType> qubits, int64_t index) {
  // Every step moves strictly towards a definition, so the walk terminates.
  for (QubitRef qubit{.value = qubits, .index = index};;) {
    const QubitStep step = stepBack(qubit);
    if (step.getKind() == QubitStep::Kind::Unknown) {
      return {};
    }
    if (step.getKind() == QubitStep::Kind::Origin) {
      // A vector value is never defined by a `qco.static`, so this covers both ends of the walk.
      return qubit.value.getDefiningOp<qco::StaticOp>();
    }
    assert(step.getKind() == QubitStep::Kind::Stepped && "unexpected QubitStep::Kind");
    qubit = step.getQubit();
  }
}

bool qcc::qvec::collectQubitProducers(TypedValue<VectorType> qubits, SmallPtrSetImpl<Operation*>& producers) {
  bool complete = true;

  for (int64_t index = 0, numElements = qubits.getType().getNumElements(); index < numElements; ++index) {
    // Every step moves strictly towards a definition, so the walk terminates.
    for (QubitRef qubit{.value = qubits, .index = index};;) {
      if (auto producer = dyn_cast_if_present<QubitSlotOpInterface>(qubit.value.getDefiningOp())) {
        producers.insert(producer);
        break;
      }

      const QubitStep step = stepBack(qubit);
      if (step.getKind() == QubitStep::Kind::Unknown) {
        complete = false;
        break;
      }
      if (step.getKind() == QubitStep::Kind::Origin) {
        break;
      }
      assert(step.getKind() == QubitStep::Kind::Stepped && "unexpected QubitStep::Kind");
      qubit = step.getQubit();
    }
  }

  return complete;
}
