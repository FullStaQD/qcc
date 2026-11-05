// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/HLEP/IR/LinearityAwareOpInterfaceImpl.h"

#include "qcc/Dialect/HLEP/IR/HLEP.h"

#include "LinearityChecker.h"

#include <llvm/ADT/SmallBitVector.h>
#include <mlir/Dialect/Func/IR/FuncOps.h>
#include <mlir/Dialect/SCF/IR/SCF.h>
#include <mlir/Interfaces/ControlFlowInterfaces.h>

using namespace mlir;
using namespace qcc::hlep;

static LogicalResult verifyLinearOperandsForwarded(Operation* op, const llvm::SmallBitVector& forwarded) {
  for (OpOperand& operand : op->getOpOperands()) {
    if (isNotPurelyClassical(operand.get().getType()) && !forwarded.test(operand.getOperandNumber())) {
      return op->emitError() << "operand #" << operand.getOperandNumber()
                             << " is subject to linearity, but is not forwarded along the control flow of this op";
    }
  }
  return success();
}

namespace {

/// Branching op whose operands subject to linearity must all be
/// forwarded into its regions or results (e.g. `scf.for` iter_args).
///
/// The RegionBranchOpInterface knows which operands correspond to which block arguments and results that
/// come next in the control flow.
/// Operands may alternatively be forgotten. Hereby we prohibit forgetting operands subject to linearity.
template <typename OpTy>
struct RegionBranchModel final : LinearityAwareOpInterface::ExternalModel<RegionBranchModel<OpTy>, OpTy> {
  static LogicalResult verifyLinearValueHandling(Operation* op) {
    auto branchOp = cast<RegionBranchOpInterface>(op);
    llvm::SmallBitVector forwarded(op->getNumOperands());
    SmallVector<RegionSuccessor> successors;
    branchOp.getSuccessorRegions(RegionBranchPoint::parent(), successors);
    for (const RegionSuccessor& successor : successors) {
      OperandRange operands = branchOp.getEntrySuccessorOperands(successor);
      if (!operands.empty()) {
        unsigned begin = operands.getBeginOperandIndex();
        forwarded.set(begin, begin + operands.size());
      }
    }
    return verifyLinearOperandsForwarded(op, forwarded);
  }
};

/// Region terminator whose operands subject to linearity must all be forwarded
/// to a region successor (e.g. `scf.yield`, `scf.condition`).
///
/// The RegionBranchTerminatorOpInterface knows which operands correspond to which block arguments and results
/// that come next in the control flow.
/// Operands may alternatively be forgotten. Hereby we prohibit forgetting operands subject to linearity.
template <typename OpTy>
struct RegionTerminatorModel final : LinearityAwareOpInterface::ExternalModel<RegionTerminatorModel<OpTy>, OpTy> {
  static LogicalResult verifyLinearValueHandling(Operation* op) {
    auto terminator = cast<RegionBranchTerminatorOpInterface>(op);
    llvm::SmallBitVector forwarded(op->getNumOperands());
    SmallVector<RegionSuccessor> successors;
    auto parentOp = dyn_cast<RegionBranchOpInterface>(op->getParentOp());
    if (!parentOp) {
      return op->emitError() << "has an operand subject to linearity, but its parent op's control flow is unknown";
    }
    parentOp.getSuccessorRegions(RegionBranchPoint(terminator), successors);
    for (const RegionSuccessor& successor : successors) {
      for (OpOperand& operand : terminator.getMutableSuccessorOperands(successor)) {
        forwarded.set(operand.getOperandNumber());
      }
    }
    return verifyLinearOperandsForwarded(op, forwarded);
  }
};

template <typename OpTy>
struct DefaultModel final : LinearityAwareOpInterface::ExternalModel<DefaultModel<OpTy>, OpTy> {};

} // namespace

void qcc::hlep::registerLinearityAwareOpInterfaceExternalModels(DialectRegistry& registry) {
  registry.addExtension(+[](MLIRContext* ctx, scf::SCFDialect* /*dialect*/) {
    scf::ForOp::attachInterface<RegionBranchModel<scf::ForOp>>(*ctx);
    scf::IfOp::attachInterface<RegionBranchModel<scf::IfOp>>(*ctx);
    scf::WhileOp::attachInterface<RegionBranchModel<scf::WhileOp>>(*ctx);
    scf::IndexSwitchOp::attachInterface<RegionBranchModel<scf::IndexSwitchOp>>(*ctx);
    scf::ExecuteRegionOp::attachInterface<RegionBranchModel<scf::ExecuteRegionOp>>(*ctx);
    scf::YieldOp::attachInterface<RegionTerminatorModel<scf::YieldOp>>(*ctx);
    scf::ConditionOp::attachInterface<RegionTerminatorModel<scf::ConditionOp>>(*ctx);
  });
  registry.addExtension(+[](MLIRContext* ctx, func::FuncDialect* /*dialect*/) {
    func::ReturnOp::attachInterface<DefaultModel<func::ReturnOp>>(*ctx);
    // TODO: Only allow calls to `hlep.halo` callees; a non-haloed callee
    // is outside the linearity check, so nothing proves that it uses its
    // linear arguments exactly once.
    func::CallOp::attachInterface<DefaultModel<func::CallOp>>(*ctx);
    func::CallIndirectOp::attachInterface<DefaultModel<func::CallIndirectOp>>(*ctx);
  });
}
