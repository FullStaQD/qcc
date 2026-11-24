// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/IR/Dialect.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"

//===----------------------------------------------------------------------===//
// Test Dialect
//===----------------------------------------------------------------------===//

#include "TestDialect.h.inc"

//===----------------------------------------------------------------------===//
// Test Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "TestOps.h.inc"

namespace qcc::test {

/// Registers the test dialect in `registry`; for the development tools only (see the dialect description).
void registerTestDialect(mlir::DialectRegistry& registry);

} // namespace qcc::test
