// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// Canonicalization patterns for `prelimhlep.lin`. They clean up after
// classical simplification of a body (typically after merging `lin` ops, see
// the `prelim-hlep-merge-lin` pass): wires the body no longer touches are
// peeled off, and ops that end up doing nothing are erased.
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include <llvm/ADT/BitVector.h>
#include <mlir/IR/PatternMatch.h>

using namespace mlir;
using namespace qcc::prelimhlep;

namespace {

/// Replaces `linOp` by a copy whose body arguments in `droppedArgs`
/// (and the matching delinearized operands) are removed, and whose body is
/// terminated by `output (delinearized) carrying (auxiliary)`. The dropped
/// arguments must be unused once the old terminator is gone. The results of
/// `linOp` are left for the caller to replace.
static LinOp rebuildLinOp(PatternRewriter& rewriter, LinOp linOp, const llvm::BitVector& droppedArgs,
                          ArrayRef<Value> delinearized, ArrayRef<Value> auxiliary) {
  Block& body = linOp.getBody().front();
  Operation* oldOutput = body.getTerminator();
  rewriter.setInsertionPoint(oldOutput);
  OutputOp::create(rewriter, oldOutput->getLoc(), delinearized, auxiliary);
  rewriter.eraseOp(oldOutput);

  SmallVector<Value> operands;
  for (auto [i, operand] : llvm::enumerate(linOp.getDelinearizedOperands())) {
    if (!droppedArgs.test(i)) {
      operands.push_back(operand);
    }
  }
  SmallVector<Type> resultTypes;
  for (Value value : delinearized) {
    resultTypes.push_back(LinType::get(rewriter.getContext(), value.getType()));
  }
  for (Value value : auxiliary) {
    resultTypes.push_back(value.getType());
  }

  rewriter.setInsertionPoint(linOp);
  auto newOp = LinOp::create(rewriter, linOp.getLoc(), resultTypes, operands);
  rewriter.inlineRegionBefore(linOp.getBody(), newOp.getBody(), newOp.getBody().end());
  newOp.getBody().front().eraseArguments(droppedArgs);
  return newOp;
}

static bool isDefinedInside(LinOp linOp, Value value) { return linOp.getBody().isAncestor(value.getParentRegion()); }

/// A body argument whose only use is as a delinearized output is a wire the
/// op does not act on: the tensor factor splits off, and the op's result is
/// just its operand.
///
///   %r0, %r1 = lin (%a : T from %q0, %b : U from %q1) { ...; output (%x, %b) }
/// ->
///   %r0 = lin (%a : T from %q0) { ...; output (%x) }    // uses of %r1 -> %q1
struct PeelPassthroughWires final : OpRewritePattern<LinOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(LinOp linOp, PatternRewriter& rewriter) const override {
    Block& body = linOp.getBody().front();
    auto output = cast<OutputOp>(body.getTerminator());
    unsigned numDelinearized = output.getDelinearizedResults().size();

    llvm::BitVector droppedArgs(body.getNumArguments());
    llvm::BitVector droppedResults(numDelinearized);
    for (BlockArgument arg : body.getArguments()) {
      if (!arg.hasOneUse()) {
        continue;
      }
      OpOperand& use = *arg.use_begin();
      if (use.getOwner() != output || use.getOperandNumber() >= numDelinearized) {
        continue;
      }
      droppedArgs.set(arg.getArgNumber());
      droppedResults.set(use.getOperandNumber());
    }
    if (droppedArgs.none()) {
      return failure();
    }

    SmallVector<Value> replacements(linOp.getNumResults());
    SmallVector<Value> delinearized;
    for (auto [j, value] : llvm::enumerate(output.getDelinearizedResults())) {
      if (droppedResults.test(j)) {
        replacements[j] = linOp.getDelinearizedOperands()[cast<BlockArgument>(value).getArgNumber()];
      } else {
        delinearized.push_back(value);
      }
    }
    SmallVector<Value> auxiliary = llvm::to_vector(output.getAuxiliaryResults());

    LinOp newOp = rebuildLinOp(rewriter, linOp, droppedArgs, delinearized, auxiliary);
    unsigned next = 0;
    for (Value& replacement : replacements) {
      if (!replacement) {
        replacement = newOp.getResult(next++);
      }
    }
    rewriter.replaceOp(linOp, replacements);
    return success();
  }
};

/// A `carrying` result that is a value captured from outside the op, or a
/// constant, does not depend on the delinearized inputs: it is forwarded
/// directly (a captured linear value passed through untouched is a tensor
/// factor the op does not act on).
struct ForwardIndependentCarriedValues final : OpRewritePattern<LinOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(LinOp linOp, PatternRewriter& rewriter) const override {
    auto output = cast<OutputOp>(linOp.getBody().front().getTerminator());
    unsigned numDelinearized = output.getDelinearizedResults().size();

    SmallVector<Value> replacements(linOp.getNumResults());
    SmallVector<Value> auxiliary;
    for (auto [k, value] : llvm::enumerate(output.getAuxiliaryResults())) {
      Value& replacement = replacements[numDelinearized + k];
      if (!isDefinedInside(linOp, value)) {
        replacement = value;
      } else if (Operation* def = value.getDefiningOp(); def != nullptr && def->hasTrait<OpTrait::ConstantLike>()) {
        rewriter.setInsertionPoint(linOp);
        replacement = rewriter.clone(*def)->getResult(cast<OpResult>(value).getResultNumber());
      } else {
        auxiliary.push_back(value);
      }
    }
    if (auxiliary.size() == output.getAuxiliaryResults().size()) {
      return failure();
    }

    SmallVector<Value> delinearized = llvm::to_vector(output.getDelinearizedResults());
    LinOp newOp =
        rebuildLinOp(rewriter, linOp, llvm::BitVector(linOp.getDelinearizedOperands().size()), delinearized, auxiliary);
    unsigned next = 0;
    for (Value& replacement : replacements) {
      if (!replacement) {
        replacement = newOp.getResult(next++);
      }
    }
    rewriter.replaceOp(linOp, replacements);
    return success();
  }
};

/// An op without operands and results is a no-op, unless its body consumes a
/// captured linear value (e.g. discards a qubit).
struct EraseTrivialLin final : OpRewritePattern<LinOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(LinOp linOp, PatternRewriter& rewriter) const override {
    if (linOp->getNumOperands() != 0 || linOp->getNumResults() != 0) {
      return failure();
    }
    WalkResult consumesCapture = linOp.getBody().walk([&](Operation* op) {
      for (Value operand : op->getOperands()) {
        if (isa<LinType>(operand.getType()) && !isDefinedInside(linOp, operand)) {
          return WalkResult::interrupt();
        }
      }
      return WalkResult::advance();
    });
    if (consumesCapture.wasInterrupted()) {
      return failure();
    }
    rewriter.eraseOp(linOp);
    return success();
  }
};

} // namespace

void LinOp::getCanonicalizationPatterns(RewritePatternSet& results, MLIRContext* context) {
  results.add<PeelPassthroughWires, ForwardIndependentCarriedValues, EraseTrivialLin>(context);
}
