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
  // Counting uses checks the affine rule only in straight-line code: a function with a single block, whose qubit ops
  // sit directly in that block. Without qubit arguments and results, no qubit enters or leaves the function either.
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

  for (OpResult result : op->getResults()) {
    // A vector result is exempt: it is legitimately taken apart (`vector.extract`, slices).
    if (isa<QubitType>(result.getType()) && !result.use_empty() && !result.hasOneUse()) {
      return op->emitOpError() << "qubit result #" << result.getResultNumber() << " has " << result.getNumUses()
                               << " uses, but qubit values are affine";
    }
  }

  // The op consumes its qubit operands, a vector as a whole. This also covers the qubits that come from an op without
  // this trait (e.g. `vector.from_elements`), where only the consumer can see a second use.
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

  // Every lane has both ends, so a qubit outside the lanes would start or end at this op.
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

  // One op creates all qubits of a function. The function has a single block (see `SingleUseQubits`), so an earlier
  // op of the same kind is found in this block.
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
