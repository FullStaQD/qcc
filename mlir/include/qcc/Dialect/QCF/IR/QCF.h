// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "qcc/Dialect/Qcc/IR/Qcc.h" // IWYU pragma: keep

#include "mlir/IR/Builders.h"
#include "mlir/IR/Dialect.h" // IWYU pragma: keep
#include "mlir/IR/Location.h"
#include "mlir/IR/OpImplementation.h" // IWYU pragma: keep
#include "mlir/IR/ValueRange.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h" // IWYU pragma: keep
#include "mlir/Interfaces/SideEffectInterfaces.h"  // IWYU pragma: keep

#include "llvm/ADT/STLFunctionalExtras.h"

//===----------------------------------------------------------------------===//
// QCF Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QCF/IR/QCFDialect.h.inc"

//===----------------------------------------------------------------------===//
// QCF Operations
//===----------------------------------------------------------------------===//

namespace qcc::qcf {

/// Builds a region of a `qcf.if` from its bindings, including the `qcf.yield`.
using IfBodyBuilderFn = llvm::function_ref<void(mlir::OpBuilder&, mlir::Location, mlir::ValueRange)>;

} // namespace qcc::qcf

#define GET_OP_CLASSES
#include "qcc/Dialect/QCF/IR/QCFOps.h.inc"
