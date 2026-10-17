// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QCF/IR/QCF.h"

using namespace mlir;
using namespace qcc::qcf;

#include "qcc/Dialect/QCF/IR/QCFDialect.cpp.inc"

//===----------------------------------------------------------------------===//
// Dialect
//===----------------------------------------------------------------------===//

void QCFDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "qcc/Dialect/QCF/IR/QCFOps.cpp.inc"
      >();
}
