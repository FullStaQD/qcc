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
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/SMLoc.h"

#include <cassert>
#include <tuple>

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
  Region* thenRegion = state.addRegion();
  if (addThenBlock) {
    builder.createBlock(thenRegion, thenRegion->end(), qubitsIn.getTypes(), locs);
  }
  Region* elseRegion = state.addRegion();
  if (addElseBlock) {
    builder.createBlock(elseRegion, elseRegion->end(), qubitsIn.getTypes(), locs);
  }
}

void IfOp::build(OpBuilder& builder, OperationState& state, Value condition, ValueRange qubitsIn,
                 IfBodyBuilderFn thenBuilder, IfBodyBuilderFn elseBuilder) {
  assert(thenBuilder && "the then region is required");
  build(builder, state, condition, qubitsIn, /*classicalTypes=*/{}, /*addThenBlock=*/true,
        /*addElseBlock=*/static_cast<bool>(elseBuilder));

  const OpBuilder::InsertionGuard guard(builder);
  Block* thenBlock = &state.regions[0]->front();
  builder.setInsertionPointToStart(thenBlock);
  thenBuilder(builder, state.location, thenBlock->getArguments());
  if (elseBuilder) {
    Block* elseBlock = &state.regions[1]->front();
    builder.setInsertionPointToStart(elseBlock);
    elseBuilder(builder, state.location, elseBlock->getArguments());
  }

  auto thenYield = cast<YieldOp>(thenBlock->getTerminator());
  const TypeRange classicalTypes = thenYield.getResults().drop_front(qubitsIn.size()).getTypes();
  assert((elseBuilder || classicalTypes.empty()) &&
         "an omitted else region requires that there are no classical results");
  state.addTypes(classicalTypes);
}

/// Parses `%cond [(%a = %a_in, ...)] [-> <result types>] <region> [else <region>] [attr-dict]`. The leading result
/// types, one per binding, also type the bound qubits.
ParseResult IfOp::parse(OpAsmParser& parser, OperationState& result) {
  OpAsmParser::UnresolvedOperand condition;
  if (parser.parseOperand(condition)) {
    return failure();
  }

  SmallVector<OpAsmParser::Argument> bindings;
  SmallVector<OpAsmParser::UnresolvedOperand> qubitsIn;
  const OptionalParseResult hasBindings = parser.parseOptionalAssignmentList(bindings, qubitsIn);
  if (hasBindings.has_value() && failed(*hasBindings)) {
    return failure();
  }

  const SMLoc typesLoc = parser.getCurrentLocation();
  SmallVector<Type> resultTypes;
  if (parser.parseOptionalArrowTypeList(resultTypes)) {
    return failure();
  }
  if (resultTypes.size() < bindings.size()) {
    return parser.emitError(typesLoc) << "expected a result type for each binding, got " << resultTypes.size()
                                      << " result type(s) for " << bindings.size() << " binding(s)";
  }
  const ArrayRef<Type> types = resultTypes;
  const ArrayRef<Type> qubitTypes = types.take_front(bindings.size());
  const auto* unbound = llvm::find_if(types.drop_front(bindings.size()), qcc::isQubitOrQubitVector);
  if (unbound != types.end()) {
    return parser.emitError(typesLoc) << "result #" << (unbound - types.begin())
                                      << " is a qubit without a binding: qubits leave only through the bindings";
  }

  if (parser.resolveOperands(qubitsIn, qubitTypes, parser.getNameLoc(), result.operands) ||
      parser.resolveOperand(condition, parser.getBuilder().getI1Type(), result.operands)) {
    return failure();
  }

  // Both regions take the bindings as their arguments.
  for (auto [binding, type] : llvm::zip_equal(bindings, qubitTypes)) {
    binding.type = type;
  }
  Region* thenRegion = result.addRegion();
  Region* elseRegion = result.addRegion();
  if (parser.parseRegion(*thenRegion, bindings)) {
    return failure();
  }
  if (succeeded(parser.parseOptionalKeyword("else")) && parser.parseRegion(*elseRegion, bindings)) {
    return failure();
  }

  if (parser.parseOptionalAttrDict(result.attributes)) {
    return failure();
  }
  result.addTypes(resultTypes);
  return success();
}

void IfOp::print(OpAsmPrinter& printer) {
  printer << " " << getCondition();
  if (!getQubitsIn().empty()) {
    // The binding list is printed once, with the names of the then region's arguments. Sibling regions number their
    // values alike, so the arguments of the else region get the same names. Not so with `--mlir-print-unique-ssa-ids`:
    // that output does not parse back (the generic form does).
    printer << " (";
    llvm::interleaveComma(llvm::zip(getThenRegion().getArguments(), getQubitsIn()), printer,
                          [&](auto binding) { printer << std::get<0>(binding) << " = " << std::get<1>(binding); });
    printer << ")";
  }
  printer.printOptionalArrowTypeList(getResultTypes());
  printer << " ";
  printer.printRegion(getThenRegion(), /*printEntryBlockArgs=*/false);
  if (!getElseRegion().empty()) {
    printer << " else ";
    printer.printRegion(getElseRegion(), /*printEntryBlockArgs=*/false);
  }
  printer.printOptionalAttrDict((*this)->getAttrs());
}

YieldOp IfOp::getThenYield() { return cast<YieldOp>(getThenBlock()->getTerminator()); }

YieldOp IfOp::getElseYield() {
  assert(getElseBlock() != nullptr && "the else region is omitted");
  return cast<YieldOp>(getElseBlock()->getTerminator());
}

void IfOp::getSuccessorRegions(RegionBranchPoint point, SmallVectorImpl<RegionSuccessor>& regions) {
  // Both regions return to the op.
  if (!point.isParent()) {
    regions.emplace_back(getOperation());
    return;
  }
  regions.emplace_back(&getThenRegion());
  // An omitted else region passes the bound qubits straight on to the results.
  if (getElseRegion().empty()) {
    regions.emplace_back(getOperation());
  } else {
    regions.emplace_back(&getElseRegion());
  }
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
