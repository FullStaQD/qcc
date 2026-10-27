// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QCirc/IR/QCirc.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/IR/BuiltinTypes.h"     // IWYU pragma: keep
#include "mlir/IR/OpImplementation.h" // IWYU pragma: keep
#include "mlir/IR/Operation.h"        // IWYU pragma: keep

using namespace mlir;
using namespace qcc::qcirc;

#include "qcc/Dialect/QCirc/IR/QCircDialect.cpp.inc"

#define GET_OP_CLASSES
#include "qcc/Dialect/QCirc/IR/QCircOps.cpp.inc"

//===----------------------------------------------------------------------===//
// Verifiers
//===----------------------------------------------------------------------===//

LogicalResult SingleOp::verify() { return qcc::detail::verifyGateParams(*this, getGateKind(), getParams()); }

LogicalResult PairOp::verify() { return qcc::detail::verifyGateParams(*this, getGateKind(), getParams()); }

//===----------------------------------------------------------------------===//
// Dialect
//===----------------------------------------------------------------------===//

void QCircDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "qcc/Dialect/QCirc/IR/QCircOps.cpp.inc"
      >();
}
