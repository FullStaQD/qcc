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
// QVec Interfaces
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVecInterfaces.h.inc"

//===----------------------------------------------------------------------===//
// QVec Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/QVec/IR/QVecOps.h.inc"

namespace qcc::qvec {

/// Traces `qubits` backwards along `QubitSlotOpInterface` and returns the first value that is not tied to an operand.
mlir::Value getNonQVecAncestor(mlir::Value qubits);

/// Trace back the qubit at `index` in the vector `qubits` to a StaticOp and return it if possible.
mlir::qco::StaticOp getStaticOpAncestor(mlir::TypedValue<mlir::VectorType> qubits, int64_t index);

} // namespace qcc::qvec
