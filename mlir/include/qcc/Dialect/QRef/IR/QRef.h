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

#include "mlir/Bytecode/BytecodeOpInterface.h"    // IWYU pragma: keep
#include "mlir/IR/Builders.h"                     // IWYU pragma: keep
#include "mlir/IR/Dialect.h"                      // IWYU pragma: keep
#include "mlir/Interfaces/SideEffectInterfaces.h" // IWYU pragma: keep

//===----------------------------------------------------------------------===//
// QRef Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QRef/IR/QRefDialect.h.inc"

//===----------------------------------------------------------------------===//
// QRef Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/QRef/IR/QRefOps.h.inc"
