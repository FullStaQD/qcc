// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QCirc/IR/QCirc.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectImplementation.h" // IWYU pragma: keep
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/TypeRange.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/ValueRange.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h" // IWYU pragma: keep

#include <cstddef>

using namespace mlir;
using namespace qcc::qcirc;

#include "qcc/Dialect/QCirc/IR/QCircDialect.cpp.inc"
#include "qcc/Dialect/QCirc/IR/QCircEnums.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/QCirc/IR/QCircAttrs.cpp.inc"

//===----------------------------------------------------------------------===//
// Custom directives
//===----------------------------------------------------------------------===//

/// Parses the types of a `single` / `pair`: `[<angle type>, ]<qubit type>`, the angle type once for all angles.
static ParseResult parseGateTypes(OpAsmParser& parser, SmallVectorImpl<Type>& paramTypes,
                                  ArrayRef<OpAsmParser::UnresolvedOperand> params, Type& qubitType) {
  if (!params.empty()) {
    Type paramType;
    if (parser.parseType(paramType) || parser.parseComma()) {
      return failure();
    }
    paramTypes.assign(params.size(), paramType);
  }
  return parser.parseType(qubitType);
}

/// Prints the types of a `single` / `pair`: `[<angle type>, ]<qubit type>`.
static void printGateTypes(OpAsmPrinter& printer, Operation* /*op*/, TypeRange paramTypes, OperandRange /*params*/,
                           Type qubitType) {
  if (!paramTypes.empty()) {
    printer << paramTypes.front() << ", "; // The type constraints guarantee they are all equal.
  }
  printer << qubitType;
}

#define GET_OP_CLASSES
#include "qcc/Dialect/QCirc/IR/QCircOps.cpp.inc"

//===----------------------------------------------------------------------===//
// Verifiers
//===----------------------------------------------------------------------===//

/// Verifies the number of gate parameters of a `single` / `pair`.
static LogicalResult verifyGateParams(Operation* op, StringRef kind, unsigned expectedNumParams, size_t numParams) {
  if (numParams != expectedNumParams) {
    return op->emitOpError() << "gate '" << kind << "' takes " << expectedNumParams << " parameter(s), got "
                             << numParams;
  }
  return success();
}

LogicalResult SingleOp::verify() {
  return verifyGateParams(*this, stringifySingleGateKind(getGateKind()),
                          SingleGateKindAttr::getNumParams(getGateKind()), getParams().size());
}

LogicalResult PairOp::verify() {
  return verifyGateParams(*this, stringifyPairGateKind(getGateKind()), PairGateKindAttr::getNumParams(getGateKind()),
                          getParams().size());
}

//===----------------------------------------------------------------------===//
// Dialect
//===----------------------------------------------------------------------===//

void QCircDialect::initialize() {
  addAttributes<
#define GET_ATTRDEF_LIST
#include "qcc/Dialect/QCirc/IR/QCircAttrs.cpp.inc"
      >();

  addOperations<
#define GET_OP_LIST
#include "qcc/Dialect/QCirc/IR/QCircOps.cpp.inc"
      >();
}
