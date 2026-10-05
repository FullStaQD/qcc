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

#include "mlir/Bytecode/BytecodeOpInterface.h" // IWYU pragma: keep
#include "mlir/IR/Builders.h"                  // IWYU pragma: keep
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dialect.h" // IWYU pragma: keep
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Interfaces/SideEffectInterfaces.h" // IWYU pragma: keep

//===----------------------------------------------------------------------===//
// QCirc Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QCirc/IR/QCircDialect.h.inc"

//===----------------------------------------------------------------------===//
// QCirc Attributes
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QCirc/IR/QCircEnums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/QCirc/IR/QCircAttrs.h.inc"

//===----------------------------------------------------------------------===//
// QCirc Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/QCirc/IR/QCircOps.h.inc"
