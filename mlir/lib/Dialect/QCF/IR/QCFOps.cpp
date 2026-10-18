// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QCF/IR/QCF.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/TypeRange.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h" // IWYU pragma: keep
#include "llvm/ADT/SmallVectorExtras.h"

#include <cassert>

using namespace mlir;
using namespace qcc::qcf;

#define GET_OP_CLASSES
#include "qcc/Dialect/QCF/IR/QCFOps.cpp.inc"

//===----------------------------------------------------------------------===//
// IfOp
//===----------------------------------------------------------------------===//

void IfOp::build(OpBuilder& builder, OperationState& state, Value condition, ValueRange qubitsIn,
                 TypeRange classicalTypes, bool addThenBlock, bool addElseBlock) {
  assert((!addElseBlock || addThenBlock) && "must not create an else block without a then block");
  assert(llvm::none_of(classicalTypes, qcc::isQubitOrQubitVector) && "qubits leave only through the bindings");
  state.addOperands(qubitsIn);
  state.addOperands(condition);
  state.addTypes(qubitsIn.getTypes());
  state.addTypes(classicalTypes);

  const SmallVector<Location> locs = llvm::map_to_vector(qubitsIn, [](Value qubit) { return qubit.getLoc(); });
  const OpBuilder::InsertionGuard guard(builder);
  for (const bool addBlock : {addThenBlock, addElseBlock}) {
    Region* region = state.addRegion();
    if (addBlock) {
      builder.createBlock(region, region->end(), qubitsIn.getTypes(), locs);
    }
  }
}

/// Parses `%cond [(%a = %a_in, ...)] [-> <result types>] <region> [else [(%b, ...)] <region>] [attr-dict]`. The
/// leading result types, one per binding, type the bound qubits and the arguments of both regions.
ParseResult IfOp::parse(OpAsmParser& parser, OperationState& result) {
  OpAsmParser::UnresolvedOperand condition;
  if (parser.parseOperand(condition)) {
    return failure();
  }
  SmallVector<OpAsmParser::Argument> bindings;
  SmallVector<OpAsmParser::UnresolvedOperand> qubitsIn;
  const OptionalParseResult hasBindings = parser.parseOptionalAssignmentList(bindings, qubitsIn);
  if ((hasBindings.has_value() && failed(*hasBindings)) || parser.parseOptionalArrowTypeList(result.types)) {
    return failure();
  }
  if (result.types.size() < qubitsIn.size()) {
    return parser.emitError(parser.getCurrentLocation())
           << "expected " << qubitsIn.size() << " qubit result type(s), one per binding, but got only "
           << result.types.size() << " result type(s)";
  }
  const auto* unbound = llvm::find_if(ArrayRef(result.types).drop_front(qubitsIn.size()), qcc::isQubitOrQubitVector);
  if (unbound != result.types.end()) {
    return parser.emitError(parser.getCurrentLocation())
           << "result #" << (unbound - result.types.begin()) << " is a qubit without a binding";
  }
  const ArrayRef<Type> qubitTypes = ArrayRef(result.types).take_front(qubitsIn.size());
  if (parser.resolveOperands(qubitsIn, qubitTypes, parser.getNameLoc(), result.operands) ||
      parser.resolveOperand(condition, parser.getBuilder().getI1Type(), result.operands)) {
    return failure();
  }

  auto parseRegion = [&](Region& region, SmallVectorImpl<OpAsmParser::Argument>& arguments) -> ParseResult {
    if (arguments.size() != qubitTypes.size()) {
      return parser.emitError(parser.getCurrentLocation())
             << "expected " << qubitTypes.size() << " argument name(s), one per binding, got " << arguments.size();
    }
    for (auto [argument, type] : llvm::zip_equal(arguments, qubitTypes)) {
      argument.type = type;
    }
    return parser.parseRegion(region, arguments);
  };
  Region* thenRegion = result.addRegion();
  Region* elseRegion = result.addRegion();
  if (parseRegion(*thenRegion, bindings)) {
    return failure();
  }
  // The else region names its own arguments.
  SmallVector<OpAsmParser::Argument> elseArguments;
  if (succeeded(parser.parseOptionalKeyword("else")) &&
      ((!qubitsIn.empty() && parser.parseArgumentList(elseArguments, OpAsmParser::Delimiter::Paren)) ||
       parseRegion(*elseRegion, elseArguments))) {
    return failure();
  }
  return parser.parseOptionalAttrDict(result.attributes);
}

void IfOp::print(OpAsmPrinter& printer) {
  printer << " " << getCondition();
  if (!getQubitsIn().empty()) {
    printer << " (";
    llvm::interleaveComma(llvm::zip(getThenRegion().getArguments(), getQubitsIn()), printer, [&](auto binding) {
      auto [argument, qubit] = binding;
      printer << argument << " = " << qubit;
    });
    printer << ")";
  }
  printer.printOptionalArrowTypeList(getResultTypes());
  printer << " ";
  printer.printRegion(getThenRegion(), /*printEntryBlockArgs=*/false);
  if (!getElseRegion().empty()) {
    printer << " else ";
    if (!getQubitsIn().empty()) {
      printer << "(" << getElseRegion().getArguments() << ") ";
    }
    printer.printRegion(getElseRegion(), /*printEntryBlockArgs=*/false);
  }
  printer.printOptionalAttrDict((*this)->getAttrs());
}

void IfOp::getSuccessorRegions(RegionBranchPoint point, SmallVectorImpl<RegionSuccessor>& regions) {
  // Both regions return to the op.
  if (!point.isParent()) {
    regions.emplace_back(getOperation());
    return;
  }
  // An omitted else region passes the bound qubits straight on to the results.
  regions.emplace_back(&getThenRegion());
  regions.push_back(getElseRegion().empty() ? RegionSuccessor(getOperation()) : RegionSuccessor(&getElseRegion()));
}

OperandRange IfOp::getEntrySuccessorOperands(RegionSuccessor /*successor*/) {
  // Every successor receives the bound qubits: a region as its arguments, an omitted else region as the results.
  return getQubitsIn();
}

ValueRange IfOp::getSuccessorInputs(RegionSuccessor successor) {
  if (successor.isOperation()) {
    return getResults();
  }
  return successor.getSuccessor()->getArguments();
}

LogicalResult IfOp::verify() {
  for (Region& region : getOperation()->getRegions()) {
    // `SingleBlock` already ensured that a block is not empty.
    if (!region.empty() && !isa<YieldOp>(region.front().back())) {
      return emitOpError() << "expects region #" << region.getRegionNumber() << " to end with 'qcf.yield'";
    }
  }
  if (getElseRegion().empty() && !getClassicalResults().empty()) {
    return emitOpError() << "must have an else region if it has classical results";
  }
  return success();
}

/// Walks back from `qubit`, an operand of `user`, along its lane through the lane ops of the block of `user`. Returns
/// the value where the walk stops: a block argument, or a result of an op that is not a lane op.
static Value walkBackAlongLane(Value qubit, Operation* user) {
  Block* block = user->getBlock();
  while (auto result = dyn_cast<OpResult>(qubit)) {
    Operation* owner = result.getOwner();
    auto laneOp = dyn_cast<qcc::QubitLaneOpInterface>(owner);
    // Dominance is verified only after all ops, so here a lane may still run in a circle.
    if (!laneOp || owner->getBlock() != block || !owner->isBeforeInBlock(user)) {
      break;
    }
    qubit = laneOp.getTiedQubitOperand(result);
    user = owner;
  }
  return qubit;
}

LogicalResult IfOp::verifyRegions() {
  // The qubit yielded at position `i` must be the one bound to argument `i`. Only a proven mismatch fails: a walk that
  // stops at an op that is not a lane op proves nothing. The region branch interface, verified before, has already
  // matched the yielded types against the result types.
  for (Region& region : getOperation()->getRegions()) {
    if (region.empty()) {
      continue;
    }
    auto yield = cast<YieldOp>(region.front().getTerminator());
    for (auto [position, qubit] : llvm::enumerate(yield.getResults().take_front(getQubitsIn().size()))) {
      auto binding = dyn_cast<BlockArgument>(walkBackAlongLane(qubit, yield));
      if (binding && binding.getOwner() == &region.front() && binding.getArgNumber() != position) {
        InFlightDiagnostic diag = emitOpError()
                                  << "region #" << region.getRegionNumber() << " yields the qubit bound to argument #"
                                  << binding.getArgNumber() << " at position #" << position
                                  << ", but a bound qubit must be yielded at the position of its binding";
        diag.attachNote(yield.getLoc()) << "yielded here";
        return diag;
      }
    }
  }
  return success();
}
