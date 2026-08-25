// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

// FIXME: check for IWYU
#include "mlir/Dialect/QCO/IR/QCODialect.h" // IWYU pragma: keep
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

namespace mlir {
class DialectRegistry;
class Value;
} // namespace mlir

//===----------------------------------------------------------------------===//
// HiSEP-Q Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/HiSEPQ/IR/HiSEPQDialect.h.inc"

//===----------------------------------------------------------------------===//
// HiSEP-Q Attributes
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/HiSEPQ/IR/HiSEPQEnums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/HiSEPQ/IR/HiSEPQAttrs.h.inc"

//===----------------------------------------------------------------------===//
// HiSEP-Q Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/HiSEPQ/IR/HiSEPQOps.h.inc"

namespace qcc::hisepq {

//  FIXME: Consider patching qco.qubit upstream.
/// Attaches `VectorElementTypeInterface` to `mlir::qco::QubitType`, which is what makes
/// `vector<Nx!qco.qubit>` a legal type. Call this on any registry that will see `hisepq` IR;
/// without it such a vector fails to parse.
void registerQubitVectorElementTypeInterfaceExternalModel(mlir::DialectRegistry& registry);

/// Traces the origin of `qubits` through ancestor ops to the first non-hisepq-dialect generated value and returns it.
mlir::Value getQubitVectorOrigin(mlir::Value qubits);

} // namespace qcc::hisepq
