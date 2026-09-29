// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/Dialect/QCO/IR/QCODialect.h" // IWYU pragma: keep
#include "mlir/Dialect/QCO/IR/QCOOps.h"
#include "mlir/IR/BuiltinTypes.h"

#include <cassert>
#include <cstdint>
#include <mlir/IR/Value.h>

namespace mlir {
class Value;
} // namespace mlir

//===----------------------------------------------------------------------===//
// QVec Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVecDialect.h.inc"

//===----------------------------------------------------------------------===//
// QVec Attributes
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVecEnums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/QVec/IR/QVecAttrs.h.inc"

//===----------------------------------------------------------------------===//
// QVec type predicates
//===----------------------------------------------------------------------===//

namespace qcc::qvec {

/// Whether `type` is a vector with element type `!qco.qubit`.
inline bool isQubitVector(mlir::Type type) {
  auto vectorType = mlir::dyn_cast<mlir::VectorType>(type);
  return vectorType && mlir::isa<mlir::qco::QubitType>(vectorType.getElementType());
}

} // namespace qcc::qvec

//===----------------------------------------------------------------------===//
// QVec Interfaces
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVecInterfaces.h.inc"

//===----------------------------------------------------------------------===//
// QVec Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/QVec/IR/QVecOps.h.inc"

namespace qcc::qvec {

/// Traces back the qubit at `index` in the vector `qubits` to a StaticOp and returns it if possible (null value if
/// not).
mlir::qco::StaticOp getStaticOpAncestor(mlir::TypedValue<mlir::VectorType> qubits, int64_t index);

} // namespace qcc::qvec
