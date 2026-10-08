// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QCirc/IR/QCirc.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectImplementation.h" // IWYU pragma: keep
#include "mlir/IR/Matchers.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/TypeRange.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/ValueRange.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h" // IWYU pragma: keep

#include <cstddef>
#include <cstdint>

using namespace mlir;
using namespace qcc::qcirc;

#include "qcc/Dialect/QCirc/IR/QCircDialect.cpp.inc"
#include "qcc/Dialect/QCirc/IR/QCircEnums.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/QCirc/IR/QCircAttrs.cpp.inc"

//===----------------------------------------------------------------------===//
// Custom directives
//===----------------------------------------------------------------------===//

/// Parses the types of a `single` / `pair`: `<qubit type>[, <angle type>]`, the angle type once for all angles.
static ParseResult parseGateTypes(OpAsmParser& parser, Type& qubitType, SmallVectorImpl<Type>& paramTypes,
                                  ArrayRef<OpAsmParser::UnresolvedOperand> params) {
  if (parser.parseType(qubitType)) {
    return failure();
  }
  if (params.empty()) {
    return success();
  }
  Type paramType;
  if (parser.parseComma() || parser.parseType(paramType)) {
    return failure();
  }
  paramTypes.assign(params.size(), paramType);
  return success();
}

/// Prints the types of a `single` / `pair`: `<qubit type>[, <angle type>]`.
static void printGateTypes(OpAsmPrinter& printer, Operation* /*op*/, Type qubitType, TypeRange paramTypes,
                           OperandRange /*params*/) {
  printer << qubitType;
  if (!paramTypes.empty()) {
    printer << ", " << paramTypes.front(); // The type constraints guarantee they are all equal.
  }
}

/// Parses the qubit type of a `global`: one type, shared by all its qubits on both sides.
static ParseResult parseGlobalQubitTypes(OpAsmParser& parser, SmallVectorImpl<Type>& qubitsInTypes,
                                         SmallVectorImpl<Type>& qubitsOutTypes,
                                         ArrayRef<OpAsmParser::UnresolvedOperand> qubitsIn) {
  Type qubitType;
  if (parser.parseType(qubitType)) {
    return failure();
  }
  qubitsInTypes.assign(qubitsIn.size(), qubitType);
  qubitsOutTypes.assign(qubitsIn.size(), qubitType);
  return success();
}

/// Prints the qubit type of a `global`: one type, shared by all its qubits on both sides.
static void printGlobalQubitTypes(OpAsmPrinter& printer, Operation* op, TypeRange qubitsInTypes,
                                  TypeRange /*qubitsOutTypes*/, OperandRange /*qubitsIn*/) {
  // An op without qubits has no operand to read the type from.
  printer << (qubitsInTypes.empty() ? Type(qcc::QubitType::get(op->getContext())) : qubitsInTypes.front());
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

LogicalResult GlobalOp::verify() {
  const auto numQubits = static_cast<int64_t>(getQubitsIn().size());
  const RankedTensorType anglesType = getAngles().getType();
  if (anglesType.getShape() != ArrayRef<int64_t>{numQubits, numQubits}) {
    return emitOpError() << "angle matrix " << anglesType << " must be " << numQubits << "x" << numQubits
                         << " to match the number of qubits";
  }

  // Only a constant matrix can be further checked.
  DenseFPElementsAttr angles;
  if (!matchPattern(getAngles(), m_Constant(&angles))) {
    return success();
  }

  auto values = angles.getValues<double>();
  auto at = [&](int64_t i, int64_t j) { return values[static_cast<size_t>((i * numQubits) + j)]; };
  for (int64_t i = 0; i < numQubits; ++i) {
    if (at(i, i) != 0.0) {
      return emitOpError() << "angle matrix must have a zero diagonal, entry (" << i << ", " << i << ") is "
                           << at(i, i);
    }
    for (int64_t j = 0; j < i; ++j) {
      if (at(i, j) != at(j, i)) {
        return emitOpError() << "angle matrix must be symmetric, entries (" << i << ", " << j << ") and (" << j << ", "
                             << i << ") differ";
      }
    }
  }
  return success();
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
