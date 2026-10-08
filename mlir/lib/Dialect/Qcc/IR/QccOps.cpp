// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/TypeRange.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Interfaces/FunctionInterfaces.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallSet.h"
#include "llvm/ADT/SmallVector.h"

#include <cstddef>
#include <cstdint>

using namespace mlir;
using namespace qcc;

#include "qcc/Dialect/Qcc/IR/QccOpInterfaces.cpp.inc"

//===----------------------------------------------------------------------===//
// Custom directives
//===----------------------------------------------------------------------===//

/// Parses the type of a `qcc.static`: one type, shared by all its qubits.
static ParseResult parseStaticTypes(OpAsmParser& parser, SmallVectorImpl<Type>& qubitTypes, DenseI64ArrayAttr indices) {
  Type qubitType;
  if (parser.parseType(qubitType)) {
    return failure();
  }
  qubitTypes.assign(static_cast<size_t>(indices.size()), qubitType);
  return success();
}

/// Prints the type of a `qcc.static`: one type, shared by all its qubits.
static void printStaticTypes(OpAsmPrinter& printer, Operation* op, TypeRange qubitTypes,
                             DenseI64ArrayAttr /*indices*/) {
  // An op without qubits has no result to read the type from.
  printer << (qubitTypes.empty() ? Type(QubitType::get(op->getContext())) : qubitTypes.front());
}

#define GET_OP_CLASSES
#include "qcc/Dialect/Qcc/IR/QccOps.cpp.inc"

//===----------------------------------------------------------------------===//
// Shared verification
//===----------------------------------------------------------------------===//

LogicalResult qcc::verifySingleUseQubits(Operation* op) {
  auto function = dyn_cast_if_present<FunctionOpInterface>(op->getParentOp());
  if (!function) {
    return op->emitOpError() << "must be directly inside a function";
  }
  if (!op->getParentRegion()->hasOneBlock()) {
    return op->emitOpError() << "must be in a single-block function";
  }
  if (llvm::any_of(function.getArgumentTypes(), isQubitOrQubitVector) ||
      llvm::any_of(function.getResultTypes(), isQubitOrQubitVector)) {
    return op->emitOpError() << "must be in a function without qubit arguments and results";
  }

  // Result qubits must only be used at most once.
  for (OpResult result : op->getResults()) {
    // A vector can legitimately be used multiple times: e.g. by taking it apart (`vector.extract`, slices).
    if (isa<QubitType>(result.getType()) && !result.use_empty() && !result.hasOneUse()) {
      return op->emitOpError() << "qubit result #" << result.getResultNumber() << " has " << result.getNumUses()
                               << " uses, but qubit values are affine";
    }
  }

  // Operand qubits must only be used once. This is not redundant with the result-rule above because qubits need not
  // come from ops carrying our trait.
  for (OpOperand& operand : op->getOpOperands()) {
    Value qubit = operand.get();
    if (isQubitOrQubitVector(qubit.getType()) && !qubit.hasOneUse()) {
      return op->emitOpError() << "qubit operand #" << operand.getOperandNumber() << " has " << qubit.getNumUses()
                               << " uses, but qubit values are affine";
    }
  }
  return success();
}

LogicalResult qcc::detail::verifyQubitLaneOpInterface(Operation* op) {
  auto laneOp = cast<QubitLaneOpInterface>(op);
  OperandRange operands = laneOp.getQubitOperands();
  ResultRange results = laneOp.getQubitResults();
  const unsigned numLanes = results.size();

  if (operands.size() != numLanes) {
    return op->emitOpError() << "has " << operands.size() << " qubit operand(s) but " << numLanes
                             << " qubit result(s): every qubit lane has both ends";
  }
  if (numLanes != 0 && results.front().getResultNumber() != 0) {
    return op->emitOpError() << "qubit results must be the leading results";
  }

  for (unsigned lane = 0; lane < numLanes; ++lane) {
    Type type = operands[lane].getType();
    if (!isQubitOrQubitVector(type)) {
      return op->emitOpError() << "qubit lane #" << lane << " must be a qubit or a vector of qubits, got " << type;
    }
    if (results[lane].getType() != type) {
      return op->emitOpError() << "qubit lane #" << lane << " enters as " << type << " but leaves as "
                               << results[lane].getType();
    }
  }

  // The lanes are all the qubits of the op: no other operand or result is a qubit.
  const unsigned firstOperand = numLanes == 0 ? 0 : operands.getBeginOperandIndex();
  for (OpOperand& operand : op->getOpOperands()) {
    const unsigned number = operand.getOperandNumber();
    const bool isInLane = number >= firstOperand && number - firstOperand < numLanes;
    if (!isInLane && isQubitOrQubitVector(operand.get().getType())) {
      return op->emitOpError() << "qubit operand #" << number << " is outside the qubit lanes";
    }
  }
  for (OpResult result : op->getResults().drop_front(numLanes)) {
    if (isQubitOrQubitVector(result.getType())) {
      return op->emitOpError() << "qubit result #" << result.getResultNumber() << " is outside the qubit lanes";
    }
  }
  return success();
}

//===----------------------------------------------------------------------===//
// StaticOp
//===----------------------------------------------------------------------===//

void StaticOp::build(OpBuilder& builder, OperationState& state, ArrayRef<int64_t> indices) {
  const SmallVector<Type> qubitTypes(indices.size(), QubitType::get(builder.getContext()));
  build(builder, state, qubitTypes, indices);
}

LogicalResult StaticOp::verify() {
  const ArrayRef<int64_t> indices = getIndices();
  if (indices.size() != getNumResults()) {
    return emitOpError() << "expected one qubit per index, got " << getNumResults() << " qubit(s) for "
                         << indices.size() << " indices";
  }

  llvm::SmallSet<int64_t, 8> seen;
  for (const int64_t index : indices) {
    if (index < 0) {
      return emitOpError() << "index must be non-negative, got " << index;
    }
    if (!seen.insert(index).second) {
      return emitOpError() << "index " << index << " appears more than once";
    }
  }

  if (!isa_and_present<func::FuncOp>((*this)->getParentOp())) {
    return emitOpError() << "must be directly inside a 'func.func'";
  }

  for (Operation* previous = getOperation()->getPrevNode(); previous != nullptr; previous = previous->getPrevNode()) {
    if (isa<StaticOp>(previous)) {
      InFlightDiagnostic diag = emitOpError()
                                << "a function has at most one 'qcc.static': one op creates all of its qubits";
      diag.attachNote(previous->getLoc()) << "the earlier 'qcc.static' is here";
      return diag;
    }
  }
  return success();
}
