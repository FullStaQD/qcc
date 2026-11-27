// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "TestDialect.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/ImplicitLocOpBuilder.h" // IWYU pragma: keep
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/TypeRange.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/SMLoc.h"

using namespace mlir;

//===----------------------------------------------------------------------===//
// Custom directives
//===----------------------------------------------------------------------===//

/// Parses the types of `values`: either one type per value, or a single type shared by all of them.
static ParseResult parseSharedTypes(OpAsmParser& parser, ArrayRef<OpAsmParser::UnresolvedOperand> values,
                                    SmallVectorImpl<Type>& types) {
  const llvm::SMLoc loc = parser.getCurrentLocation();
  if (parser.parseTypeList(types)) {
    return failure();
  }
  if (types.size() == 1) {
    const Type shared = types.front();
    types.assign(values.size(), shared);
    return success();
  }
  if (types.size() != values.size()) {
    return parser.emitError(loc) << "expected 1 or " << values.size() << " types, got " << types.size();
  }
  return success();
}

/// Prints the types of `values`, writing a type shared by all of them only once.
static void printSharedTypes(OpAsmPrinter& printer, Operation* /*op*/, OperandRange /*values*/, TypeRange types) {
  if (llvm::all_equal(types)) {
    printer << types.front();
    return;
  }
  llvm::interleaveComma(types, printer);
}

//===----------------------------------------------------------------------===//
// Test Dialect
//===----------------------------------------------------------------------===//

#include "TestDialect.cpp.inc"

#define GET_OP_CLASSES
#include "TestOps.cpp.inc"

void qcc::test::TestDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "TestOps.cpp.inc"
      >();
}

void qcc::test::registerTestDialect(DialectRegistry& registry) { registry.insert<TestDialect>(); }
