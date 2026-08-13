// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Aux_/IR/Aux_.h"

using namespace mlir;
using namespace qcc::aux;

#include "qcc/Dialect/Aux_/IR/AuxDialect.cpp.inc"

#define GET_OP_CLASSES
#include "qcc/Dialect/Aux_/IR/AuxOps.cpp.inc"

void AuxDialect::initialize() {
  addTypes<>();

  addOperations<
#define GET_OP_LIST
#include "qcc/Dialect/Aux_/IR/AuxOps.cpp.inc"
      >();
}

LogicalResult RecordMemRefOp::verify() {
  // Access your op's arguments/operands via their TableGen names:
  auto memRefType = getValue().getType();

  // Ensure the memref has rank 1 and identity layout (i.e., no strides or offsets)
  if (memRefType.getRank() != 1 || !memRefType.getLayout().isIdentity()) {
    return emitOpError("expected a flat memref but got memref with rank")
           << memRefType.getRank() << " and layout " << memRefType.getLayout();
  }

  if (!memRefType.hasStaticShape()) {
    return emitOpError("expected memref to have a fully static shape, but got dynamic shape ") << memRefType;
  }

  // Ensure the element type is an integer
  if (!memRefType.getElementType().isInteger()) {
    return emitOpError("expected memref element type to be an integer, but got ") << memRefType.getElementType();
  }

  // Return success if all checks pass
  return success();
}
