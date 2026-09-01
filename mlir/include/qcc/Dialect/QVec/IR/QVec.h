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

#include "llvm/ADT/SmallPtrSet.h"

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

/// Trace back the qubit at `index` in the vector `qubits` to a StaticOp and return it if possible (null value if not).
mlir::qco::StaticOp getStaticOpAncestor(mlir::TypedValue<mlir::VectorType> qubits, int64_t index);

/// Adds the `qvec` operations that produced any element of `qubits` to `producers`.
///
/// Walks back through everything that only moves qubits around, so it finds the producer even when the vector was
/// taken apart and put back together in between.
///
/// Returns false if an element could not be traced, because some operation on the way is one this walk cannot look
/// through. `producers` then holds what was found, which is a subset of the real producers. Callers that rely on
/// seeing all of them must treat that as a failure.
bool collectQubitProducers(mlir::TypedValue<mlir::VectorType> qubits,
                           llvm::SmallPtrSetImpl<mlir::Operation*>& producers);

} // namespace qcc::qvec
