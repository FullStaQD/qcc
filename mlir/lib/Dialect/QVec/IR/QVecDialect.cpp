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
#include "mlir/Support/LogicalResult.h"

#include "llvm/ADT/TypeSwitch.h" // IWYU pragma: keep

#include <cstddef>
#include <utility>

using namespace mlir;
using namespace qcc::qvec;

#include "qcc/Dialect/QVec/IR/QVecDialect.cpp.inc"
#include "qcc/Dialect/QVec/IR/QVecEnums.cpp.inc"

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
// Qubit vector origin
//===----------------------------------------------------------------------===//

Value qcc::qvec::getNonQVecAncestor(Value qubits) {
  while (auto result = dyn_cast<OpResult>(qubits)) {
    auto next =
        TypeSwitch<Operation*, Value>(result.getOwner())
            .Case<SingleOp>([](SingleOp op) { return op.getQubitsIn(); })
            .Case<PairOp>([&](PairOp op) { return result.getResultNumber() == 0 ? op.getLhsIn() : op.getRhsIn(); })
            // Only the qubit result threads through; the bits are new.
            .Case<MzOp>([&](MzOp op) { return result.getResultNumber() == 0 ? op.getQubitsIn() : Value(); })
            .Default([](Operation*) { return Value(); });
    if (!next) {
      break;
    }
    qubits = next;
  }

  // FIXME: assert that this is not a qvec operation?
  return qubits;
}

qco::StaticOp qcc::qvec::getStaticOpAncestor(TypedValue<VectorType> qubits, int64_t index) {
  // Every iteration steps strictly towards a definition, so the walk terminates.
  while (true) {
    Operation* definingOp = getNonQVecAncestor(qubits).getDefiningOp();
    if (definingOp == nullptr) {
      return {}; // A block argument. Nothing to look inside.
    }

    Value element;
    if (auto fromElementsOp = dyn_cast<vector::FromElementsOp>(definingOp)) {
      ValueRange elements = fromElementsOp.getElements();
      if (index < 0 || std::cmp_greater_equal(index, elements.size())) {
        return {};
      }
      element = elements[static_cast<size_t>(index)];
    } else if (auto broadcastOp = dyn_cast<vector::BroadcastOp>(definingOp)) {
      // A qubit vector holds distinct qubits, but the case of "trivial" broadcast to a vector with a single element
      // applies still.
      if (broadcastOp.getResultVectorType().getNumElements() != 1 || index != 0) {
        return {};
      }
      element = broadcastOp.getSource();
    } else if (auto shapeCastOp = dyn_cast<vector::ShapeCastOp>(definingOp)) { // FIXME: do we need it?
      // Rank-1 to rank-1 keeps the linear index; any other reshape would have to remap it.
      if (shapeCastOp.getSourceVectorType().getRank() != 1 || shapeCastOp.getResultVectorType().getRank() != 1) {
        return {};
      }
      qubits = shapeCastOp.getSource();
      continue;
    } else {
      return {};
    }

    auto staticOp = element.getDefiningOp<qco::StaticOp>();
    if (staticOp) {
      return staticOp;
    }

    // The element may itself be read out of another qubit vector, in which case we iteratively trace further.
    auto extractOp = element.getDefiningOp<vector::ExtractOp>();
    if (!extractOp) {
      return {};
    }

    if (extractOp.hasDynamicPosition() || extractOp.getStaticPosition().size() != 1) {
      return {};
    }
    qubits = extractOp.getSource();
    index = extractOp.getStaticPosition().front();
  }
}
