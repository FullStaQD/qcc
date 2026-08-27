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

#include <cstdint>
#include <mlir/IR/Value.h>

namespace mlir {
class DialectRegistry;
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
// QVec Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/QVec/IR/QVecOps.h.inc"

namespace qcc::qvec {

//  FIXME: Consider patching qco.qubit upstream.
/// Attaches `VectorElementTypeInterface` to `mlir::qco::QubitType`, which is what makes
/// `vector<Nx!qco.qubit>` a legal type. Call this on any registry that will see `qvec` IR;
/// without it such a vector fails to parse.
void registerQubitVectorElementTypeInterfaceExternalModel(mlir::DialectRegistry& registry);

/// Traces the origin of `qubits` through parent ops to the first non-qvec-dialect generated value and returns it.
mlir::Value getNonQVecAncestor(mlir::Value qubits);

/// Trace back the qubit at `index` in the vector `qubits` to a StaticOp and return it if possible.
mlir::qco::StaticOp getStaticOpAncestor(mlir::TypedValue<mlir::VectorType> qubits, int64_t index);

} // namespace qcc::qvec
