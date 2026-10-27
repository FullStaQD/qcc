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
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/TypeRange.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Interfaces/FunctionInterfaces.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h" // IWYU pragma: keep

#include <cstddef>
#include <cstdint>
#include <optional>

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

/// Prints the type of a `qcc.static` or `qcc.static_ref`: one type, shared by all its qubits.
static void printStaticTypes(OpAsmPrinter& printer, Operation* op, TypeRange qubitTypes,
                             DenseI64ArrayAttr /*indices*/) {
  if (!qubitTypes.empty()) {
    printer << qubitTypes.front();
    return;
  }
  // An op without qubits has no result to read the type from.
  MLIRContext* ctx = op->getContext();
  printer << (isa<StaticRefOp>(op) ? Type(QubitRefType::get(ctx)) : Type(QubitType::get(ctx)));
}

static ParseResult parseRefType(OpAsmParser& parser, Type& refType, Type& valueType) {
  const SMLoc loc = parser.getCurrentLocation();
  if (parser.parseType(refType)) {
    return failure();
  }
  auto ref = dyn_cast<RefType>(refType);
  if (ref == nullptr) {
    return parser.emitError(loc) << "expected a '!qcc.ref' type, got " << refType;
  }
  valueType = ref.getElementType();
  return success();
}

/// Prints the type of a `qcc.ref.load` or `qcc.ref.store`: the reference type only.
static void printRefType(OpAsmPrinter& printer, Operation* /*op*/, Type refType, Type /*valueType*/) {
  printer << refType;
}

#define GET_OP_CLASSES
#include "qcc/Dialect/Qcc/IR/QccOps.cpp.inc"

//===----------------------------------------------------------------------===//
// Shared verification
//===----------------------------------------------------------------------===//

LogicalResult qcc::detail::verifyNoMultiUseQubits(Operation* op) {
  Operation* parent = op->getParentOp();
  if (parent == nullptr || !parent->hasTrait<QubitScope>()) {
    auto function = dyn_cast_if_present<FunctionOpInterface>(parent);
    if (!function) {
      return op->emitOpError() << "must be directly inside a function or a qubit scope";
    }
    // A qubit scope verifies its regions itself (see `verifyQubitScope`). Hence we only check functions here.
    if (!op->getParentRegion()->hasOneBlock()) {
      return op->emitOpError() << "must be in a single-block function";
    }
    if (llvm::any_of(function.getArgumentTypes(), isQubitOrQubitVector) ||
        llvm::any_of(function.getResultTypes(), isQubitOrQubitVector)) {
      return op->emitOpError() << "must be in a function without qubit arguments and results";
    }
  }

  // Result qubits must only be used at most once.
  for (OpResult result : op->getResults()) {
    // A vector can legitimately be used multiple times: e.g. by taking it apart (`vector.extract`, slices).
    if (isa<QubitType>(result.getType()) && result.hasNUsesOrMore(2)) {
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

LogicalResult qcc::detail::verifyQubitScope(Operation* op) {
  // No capture. A nested qubit scope verifies its own regions, which suffices: a qubit from outside of `op` is also
  // from outside of the nested scope.
  for (Region& region : op->getRegions()) {
    const WalkResult walk = region.walk<WalkOrder::PreOrder>([&](Operation* nested) {
      for (OpOperand& operand : nested->getOpOperands()) {
        Value value = operand.get();
        if (!isQubitOrQubitVector(value.getType())) {
          continue;
        }
        Region* valueRegion = value.getParentRegion();
        if (valueRegion == nullptr) {
          nested->emitError("operation's operand is unlinked");
          return WalkResult::interrupt();
        }
        Operation* valueParent = valueRegion->getParentOp();
        if (valueParent == nullptr || !op->isAncestor(valueParent)) {
          InFlightDiagnostic diag = nested->emitOpError()
                                    << "illegal capture of qubit operand #" << operand.getOperandNumber();
          diag.attachNote(op->getLoc()) << "qubit scope here";
          return WalkResult::interrupt();
        }
      }
      return nested->hasTrait<QubitScope>() ? WalkResult::skip() : WalkResult::advance();
    });
    if (walk.wasInterrupted()) {
      return failure();
    }
  }

  // Qubit bindings must be used at most once. We do not check vectors (more complex).
  for (Region& region : op->getRegions()) {
    for (BlockArgument binding : region.getArguments()) {
      if (isa<QubitType>(binding.getType()) && binding.hasNUsesOrMore(2)) {
        return op->emitOpError() << "qubit binding #" << binding.getArgNumber() << " of region #"
                                 << region.getRegionNumber() << " has " << binding.getNumUses()
                                 << " uses, but qubit values are affine";
      }
    }
  }
  return success();
}

unsigned qcc::detail::getNumLeadingQubits(TypeRange types) {
  unsigned numQubits = 0;
  for (Type type : types) {
    if (!isQubitOrQubitVector(type)) {
      break;
    }
    ++numQubits;
  }
  return numQubits;
}

LogicalResult qcc::detail::verifyQubitLaneOpInterface(Operation* op) {
  const unsigned numQubitOperands = getNumLeadingQubits(op->getOperandTypes());
  const unsigned numQubitResults = getNumLeadingQubits(op->getResultTypes());

  // The qubits lead: no qubit follows a non-qubit.
  for (OpOperand& operand : op->getOpOperands().drop_front(numQubitOperands)) {
    if (isQubitOrQubitVector(operand.get().getType())) {
      return op->emitOpError() << "qubit operand #" << operand.getOperandNumber()
                               << " follows a non-qubit operand: the qubit operands must be the leading operands";
    }
  }
  for (OpResult result : op->getResults().drop_front(numQubitResults)) {
    if (isQubitOrQubitVector(result.getType())) {
      return op->emitOpError() << "qubit result #" << result.getResultNumber()
                               << " follows a non-qubit result: the qubit results must be the leading results";
    }
  }

  if (numQubitOperands != numQubitResults) {
    return op->emitOpError() << "has " << numQubitOperands << " qubit operand(s) but " << numQubitResults
                             << " qubit result(s): every qubit lane has both ends";
  }

  for (unsigned lane = 0; lane < numQubitResults; ++lane) {
    Type operandType = op->getOperand(lane).getType();
    Type resultType = op->getResult(lane).getType();
    if (operandType != resultType) {
      return op->emitOpError() << "qubit lane #" << lane << " enters as " << operandType << " but leaves as "
                               << resultType;
    }
  }
  return success();
}

Value qcc::walkBackAlongLane(OpOperand& qubitUse) {
  Value qubit = qubitUse.get();
  Operation* user = qubitUse.getOwner();
  Block* block = user->getBlock();

  while (auto result = dyn_cast<OpResult>(qubit)) {
    Operation* owner = result.getOwner();
    auto laneOp = dyn_cast<QubitLaneOpInterface>(owner);
    // Dominance may not be verified yet, so a lane may still run in a circle.
    if (!laneOp || owner->getBlock() != block || !owner->isBeforeInBlock(user)) {
      break;
    }
    qubit = laneOp.getTiedQubitOperand(result);
    user = owner;
  }

  return qubit;
}

//===----------------------------------------------------------------------===//
// Gates
//===----------------------------------------------------------------------===//

ParseResult qcc::parseGateTypes(OpAsmParser& parser, SmallVectorImpl<Type>& paramTypes,
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

void qcc::printGateTypes(OpAsmPrinter& printer, Operation* /*op*/, TypeRange paramTypes, OperandRange /*params*/,
                         Type qubitType) {
  if (!paramTypes.empty()) {
    printer << paramTypes.front() << ", "; // The type constraints guarantee they are all equal.
  }
  printer << qubitType;
}

/// Verifies that the gate `kind`, which takes `expectedNumParams` parameters, has `numParams`.
static LogicalResult verifyNumGateParams(Operation* op, StringRef kind, unsigned expectedNumParams, size_t numParams) {
  if (numParams != expectedNumParams) {
    return op->emitOpError() << "gate '" << kind << "' takes " << expectedNumParams << " parameter(s), got "
                             << numParams;
  }
  return success();
}

LogicalResult qcc::detail::verifyGateParams(Operation* op, SingleGateKind kind, ValueRange params) {
  return verifyNumGateParams(op, stringifySingleGateKind(kind), SingleGateKindAttr::getNumParams(kind), params.size());
}

LogicalResult qcc::detail::verifyGateParams(Operation* op, PairGateKind kind, ValueRange params) {
  return verifyNumGateParams(op, stringifyPairGateKind(kind), PairGateKindAttr::getNumParams(kind), params.size());
}

//===----------------------------------------------------------------------===//
// StaticOp and StaticRefOp
//===----------------------------------------------------------------------===//

/// Verifies the indices of a `qcc.static` or `qcc.static_ref`: one per qubit, non-negative and strictly increasing.
static LogicalResult verifyStaticIndices(Operation* op, ArrayRef<int64_t> indices) {
  if (indices.size() != op->getNumResults()) {
    return op->emitOpError() << "expected one qubit per index, got " << op->getNumResults() << " qubit(s) for "
                             << indices.size() << " indices";
  }

  // The indices must increase, so a non-negative first index covers all of them.
  if (!indices.empty() && indices.front() < 0) {
    return op->emitOpError() << "index must be non-negative, got " << indices.front();
  }
  for (size_t i = 1; i < indices.size(); ++i) {
    if (indices[i] <= indices[i - 1]) {
      return op->emitOpError() << "indices must be strictly increasing, got " << indices[i] << " after "
                               << indices[i - 1];
    }
  }
  return success();
}

void StaticOp::build(OpBuilder& builder, OperationState& state, ArrayRef<int64_t> indices) {
  const SmallVector<Type> qubitTypes(indices.size(), QubitType::get(builder.getContext()));
  build(builder, state, qubitTypes, indices);
}

LogicalResult StaticOp::verify() {
  if (failed(verifyStaticIndices(*this, getIndices()))) {
    return failure();
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

void StaticRefOp::build(OpBuilder& builder, OperationState& state, ArrayRef<int64_t> indices) {
  const SmallVector<Type> refTypes(indices.size(), QubitRefType::get(builder.getContext()));
  build(builder, state, refTypes, indices);
}

LogicalResult StaticRefOp::verify() { return verifyStaticIndices(*this, getIndices()); }

std::optional<int64_t> qcc::getStaticRefIndex(Value ref) {
  auto staticRef = ref.getDefiningOp<StaticRefOp>();
  if (!staticRef) {
    return std::nullopt;
  }
  const ArrayRef<int64_t> indices = staticRef.getIndices();
  const unsigned resultNumber = cast<OpResult>(ref).getResultNumber();
  // Verifiers may call this before the op is verified, i.e. before one index per result is ensured.
  return resultNumber < indices.size() ? std::optional(indices[resultNumber]) : std::nullopt;
}

//===----------------------------------------------------------------------===//
// AllocOp and DeallocOp
//===----------------------------------------------------------------------===//

LogicalResult AllocOp::verify() {
  auto arrayType = dyn_cast<RankedTensorType>(getQubits().getType());
  const bool hasDynamicSize = arrayType && arrayType.isDynamicDim(0);
  if (hasDynamicSize && !getDynamicSize()) {
    return emitOpError() << "requires a size operand for an array of dynamic size";
  }
  if (!hasDynamicSize && getDynamicSize()) {
    return emitOpError() << "has a size operand, but " << getQubits().getType() << " has no dynamic size";
  }
  return success();
}

LogicalResult DeallocOp::verify() {
  // Only a static qubit given directly is caught: the verifier does not trace the qubits of an array.
  if (const std::optional<int64_t> index = getStaticRefIndex(getQubits())) {
    return emitOpError() << "cannot free static qubit " << *index << ": only qubits from 'qcc.alloc' can be freed";
  }
  return success();
}

//===----------------------------------------------------------------------===//
// RefLoadOp and RefStoreOp
//===----------------------------------------------------------------------===//

LogicalResult RefLoadOp::verify() {
  Type elementType = getRef().getType().getElementType();
  if (getResult().getType() != elementType) {
    return emitOpError() << "cannot load a value of type " << getResult().getType() << " from a reference to "
                         << elementType;
  }
  return success();
}

LogicalResult RefStoreOp::verify() {
  Type elementType = getRef().getType().getElementType();
  if (getValue().getType() != elementType) {
    return emitOpError() << "cannot store a value of type " << getValue().getType() << " in a reference to "
                         << elementType;
  }
  return success();
}
