// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// Merges chains of `prelimhlep.lin` ops so that their bodies can be
// simplified classically (see the pass description in Passes.td).
//
// Two patterns expose classical structure, and the canonicalization patterns
// of all loaded dialects exploit it, all in one greedy rewrite:
//
// - `MergeLinChain` splices a `lin` op into the `lin` op consuming one of its
//   linearized results. This is the composition theorem, read from right to
//   left: `Lin g . Lin f` becomes `Lin (g . f)`, and the measurement results
//   of `f` stay `carrying` results of the merged op.
//
// - `PromoteCapturedLinValues` turns a captured linear value into a
//   delinearized operand when the body only applies nested `lin` ops to it
//   (possibly under `scf.if`) and hands it to the terminator. The nested ops
//   are inlined, so the body becomes classical in that value.
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"
#include "qcc/Dialect/PrelimHLEP/Transforms/Passes.h"

#include <llvm/ADT/MapVector.h>
#include <llvm/ADT/SetVector.h>
#include <llvm/ADT/SmallBitVector.h>
#include <mlir/Dialect/Arith/IR/Arith.h>
#include <mlir/Dialect/SCF/IR/SCF.h>
#include <mlir/IR/IRMapping.h>
#include <mlir/IR/Matchers.h>
#include <mlir/IR/PatternMatch.h>
#include <mlir/Transforms/GreedyPatternRewriteDriver.h>

namespace qcc {
using namespace mlir;
namespace hlep = qcc::prelimhlep;

#define GEN_PASS_DEF_PRELIMHLEPMERGELIN
#include "qcc/Dialect/PrelimHLEP/Transforms/Passes.h.inc"

namespace {

using hlep::LinOp;
using hlep::LinType;
using hlep::OutputOp;

static OutputOp getOutput(LinOp linOp) { return cast<OutputOp>(linOp.getBody().front().getTerminator()); }

static unsigned getNumDelinearizedResults(LinOp linOp) { return getOutput(linOp).getDelinearizedResults().size(); }

static bool isDefinedInside(LinOp linOp, Value value) { return linOp.getBody().isAncestor(value.getParentRegion()); }

/// Values used in the body of `linOp` but defined outside of it.
static SetVector<Value> getCapturedValues(LinOp linOp) {
  SetVector<Value> captured;
  linOp.getBody().walk([&](Operation* op) {
    for (Value operand : op->getOperands()) {
      if (!isDefinedInside(linOp, operand)) {
        captured.insert(operand);
      }
    }
  });
  return captured;
}

/// Whether `value` is available at `op`, given that it is available after
/// `op`'s block has been entered.
static bool isDefinedBefore(Value value, Operation* op) {
  Operation* def = value.getDefiningOp();
  if (def == nullptr || def->getBlock() != op->getBlock()) {
    return true;
  }
  return def->isBeforeInBlock(op);
}

//===----------------------------------------------------------------------===//
// MergeLinChain
//===----------------------------------------------------------------------===//

/// Merges `producer` into `consumer`, which delinearizes at least one
/// linearized result of `producer`:
///
///   %p:2 = lin (%a from %q) { ...A...; output (%x, %y) carrying (%m) }
///   %c   = lin (%b from %p#0) { ...B(%b, %p#2)...; output (%z) }
/// ->
///   %c, %p1, %m = lin (%a from %q) {
///     ...A...; ...B(%x, %m)...; output (%z, %y) carrying (%m)
///   }
///
/// Merged results are laid out as: the consumer's linearized results, the
/// producer's linearized results the consumer does not delinearize, the
/// producer's `carrying` results (except linear ones only the consumer uses),
/// the consumer's `carrying` results.
struct MergeLinChain final : OpRewritePattern<LinOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(LinOp consumer, PatternRewriter& rewriter) const override {
    for (Value operand : consumer.getDelinearizedOperands()) {
      auto producer = operand.getDefiningOp<LinOp>();
      if (!producer || producer->getBlock() != consumer->getBlock() ||
          cast<OpResult>(operand).getResultNumber() >= getNumDelinearizedResults(producer)) {
        continue;
      }
      if (Operation* insertionPoint = findInsertionPoint(producer, consumer)) {
        merge(producer, consumer, insertionPoint, rewriter);
        return success();
      }
    }
    return failure();
  }

private:
  /// The merged op replaces both ops at one position. At the consumer's
  /// position, every other user of the producer's results must come after the
  /// consumer; at the producer's position, everything the consumer uses (other
  /// than the producer's results) must come before the producer. Returns
  /// nullptr if neither works, or if the consumer's body captures a linearized
  /// result of the producer (the merged body only has it delinearized).
  static Operation* findInsertionPoint(LinOp producer, LinOp consumer) {
    unsigned numDelinearized = getNumDelinearizedResults(producer);
    bool atConsumer = true;
    for (OpResult result : producer->getResults()) {
      for (Operation* user : result.getUsers()) {
        if (user == consumer) {
          // Delinearizing a `carrying` result of the producer would need it
          // as an operand of the merged op, which defines it. A delinearized
          // result must not have other uses, which can be the case in
          // intermediate states of other patterns (e.g. `scf.if` combination).
          if (result.getResultNumber() >= numDelinearized || !result.hasOneUse()) {
            return nullptr;
          }
          continue;
        }
        if (consumer->isProperAncestor(user)) {
          if (result.getResultNumber() < numDelinearized) {
            return nullptr;
          }
          continue;
        }
        Operation* userInBlock = consumer->getBlock()->findAncestorOpInBlock(*user);
        if (userInBlock->isBeforeInBlock(consumer)) {
          atConsumer = false;
        }
      }
    }
    if (atConsumer) {
      return consumer;
    }

    SetVector<Value> needed = getCapturedValues(consumer);
    needed.insert(consumer.getDelinearizedOperands().begin(), consumer.getDelinearizedOperands().end());
    for (Value value : needed) {
      if (value.getDefiningOp() != producer && !isDefinedBefore(value, producer)) {
        return nullptr;
      }
    }
    return producer;
  }

  static void merge(LinOp producer, LinOp consumer, Operation* insertionPoint, PatternRewriter& rewriter) {
    OutputOp producerOutput = getOutput(producer);
    OutputOp consumerOutput = getOutput(consumer);
    unsigned numProducerDelinearized = producerOutput.getDelinearizedResults().size();
    unsigned numConsumerDelinearized = consumerOutput.getDelinearizedResults().size();

    // Operands: all of the producer's, then the consumer's that do not come
    // from the producer.
    SmallVector<Value> operands = llvm::to_vector(producer.getDelinearizedOperands());
    llvm::SmallBitVector consumed(numProducerDelinearized);
    for (Value operand : consumer.getDelinearizedOperands()) {
      if (operand.getDefiningOp() == producer) { // A linearized result, see findInsertionPoint.
        consumed.set(cast<OpResult>(operand).getResultNumber());
      } else {
        operands.push_back(operand);
      }
    }

    SmallVector<Type> resultTypes =
        llvm::to_vector(TypeRange(consumer->getResultTypes()).take_front(numConsumerDelinearized));
    for (unsigned i = 0; i < numProducerDelinearized; ++i) {
      if (!consumed.test(i)) {
        resultTypes.push_back(producer.getResult(i).getType());
      }
    }
    // A linear `carrying` result of the producer that the consumer captures is
    // consumed inside the merged body. Classical ones (measurement results)
    // stay results even if only the consumer used them.
    auto producerAuxiliaryResults = producer->getResults().drop_front(numProducerDelinearized);
    llvm::SmallBitVector keptAuxiliary(producerAuxiliaryResults.size(), true);
    for (auto [k, result] : llvm::enumerate(producerAuxiliaryResults)) {
      if (isa<LinType>(result.getType()) &&
          llvm::all_of(result.getUsers(), [&](Operation* user) { return consumer->isProperAncestor(user); })) {
        keptAuxiliary.reset(k);
      } else {
        resultTypes.push_back(result.getType());
      }
    }
    llvm::append_range(resultTypes, TypeRange(consumer->getResultTypes()).drop_front(numConsumerDelinearized));

    rewriter.setInsertionPoint(insertionPoint);
    Location loc = rewriter.getFusedLoc({producer.getLoc(), consumer.getLoc()});
    auto merged = LinOp::create(rewriter, loc, resultTypes, operands);
    SmallVector<Type> argTypes;
    SmallVector<Location> argLocs;
    for (Value operand : operands) {
      argTypes.push_back(cast<LinType>(operand.getType()).getElementType());
      argLocs.push_back(operand.getLoc());
    }
    Block* body = rewriter.createBlock(&merged.getBody(), {}, argTypes, argLocs);

    // Producer body.
    IRMapping mapping;
    unsigned nextArg = 0;
    for (BlockArgument arg : producer.getBody().getArguments()) {
      mapping.map(arg, body->getArgument(nextArg++));
    }
    for (Operation& op : producer.getBody().front().without_terminator()) {
      rewriter.clone(op, mapping);
    }
    SmallVector<Value> producerDelinearized;
    for (Value value : producerOutput.getDelinearizedResults()) {
      producerDelinearized.push_back(mapping.lookupOrDefault(value));
    }
    SmallVector<Value> producerAuxiliary;
    for (Value value : producerOutput.getAuxiliaryResults()) {
      producerAuxiliary.push_back(mapping.lookupOrDefault(value));
    }

    // Consumer body, reading the producer's outputs directly.
    for (auto [arg, operand] : llvm::zip(consumer.getBody().getArguments(), consumer.getDelinearizedOperands())) {
      if (operand.getDefiningOp() == producer) {
        mapping.map(arg, producerDelinearized[cast<OpResult>(operand).getResultNumber()]);
      } else {
        mapping.map(arg, body->getArgument(nextArg++));
      }
    }
    for (auto [result, value] :
         llvm::zip(producer.getResults().drop_front(numProducerDelinearized), producerAuxiliary)) {
      mapping.map(result, value);
    }
    for (Operation& op : consumer.getBody().front().without_terminator()) {
      rewriter.clone(op, mapping);
    }

    SmallVector<Value> delinearized;
    for (Value value : consumerOutput.getDelinearizedResults()) {
      delinearized.push_back(mapping.lookupOrDefault(value));
    }
    for (unsigned i = 0; i < numProducerDelinearized; ++i) {
      if (!consumed.test(i)) {
        delinearized.push_back(producerDelinearized[i]);
      }
    }
    SmallVector<Value> auxiliary;
    for (auto [k, value] : llvm::enumerate(producerAuxiliary)) {
      if (keptAuxiliary.test(k)) {
        auxiliary.push_back(value);
      }
    }
    for (Value value : consumerOutput.getAuxiliaryResults()) {
      auxiliary.push_back(mapping.lookupOrDefault(value));
    }
    OutputOp::create(rewriter, consumerOutput.getLoc(), delinearized, auxiliary);

    // Rewire the results in the layout documented above.
    unsigned next = 0;
    for (unsigned i = 0; i < numConsumerDelinearized; ++i) {
      rewriter.replaceAllUsesWith(consumer.getResult(i), merged.getResult(next++));
    }
    for (unsigned i = 0; i < numProducerDelinearized; ++i) {
      if (!consumed.test(i)) {
        rewriter.replaceAllUsesWith(producer.getResult(i), merged.getResult(next++));
      }
    }
    for (auto [k, result] : llvm::enumerate(producerAuxiliaryResults)) {
      if (keptAuxiliary.test(k)) {
        rewriter.replaceAllUsesWith(result, merged.getResult(next++));
      }
    }
    for (OpResult result : consumer->getResults().drop_front(numConsumerDelinearized)) {
      rewriter.replaceAllUsesWith(result, merged.getResult(next++));
    }
    rewriter.eraseOp(consumer);
    rewriter.eraseOp(producer);
  }
};

//===----------------------------------------------------------------------===//
// PromoteCapturedLinValues
//===----------------------------------------------------------------------===//

/// What promoting a captured value to a delinearized operand of a `lin` op
/// entails. Promotion is closed under the flow of the value: every linear
/// value it flows into becomes classical too.
struct PromotionPlan {
  /// Captured values that become delinearized operands, in order.
  SetVector<Value> promoted;
  /// All linear values that become classical (including `promoted`).
  DenseSet<Value> converted;
  /// Nested `lin` ops whose bodies get inlined.
  DenseSet<Operation*> inlined;
  /// `scf.if` ops some of whose results become classical.
  DenseSet<Operation*> ifs;
};

/// Checks whether `capture` can be promoted in `linOp`: its uses (and those
/// of the values it flows into) must be delinearized operands of nested `lin`
/// ops, `scf.if` yields, or `carrying` operands of `linOp`'s terminator.
///
/// Nested `lin` ops with classical `carrying` results are not inlined: those
/// are measurement results, and inlining would drop the measurement (the
/// outcome would become a coherent function of the delinearized inputs).
static FailureOr<PromotionPlan> analyzePromotion(LinOp linOp, Value capture) {
  PromotionPlan plan;
  SmallVector<Value> worklist;
  auto enqueue = [&](Value value) {
    if (plan.converted.insert(value).second) {
      worklist.push_back(value);
      if (!isDefinedInside(linOp, value)) {
        plan.promoted.insert(value);
      }
    }
  };

  OutputOp output = getOutput(linOp);
  unsigned numDelinearized = output.getDelinearizedResults().size();
  SmallVector<std::pair<scf::IfOp, unsigned>> ifResults;

  enqueue(capture);
  while (!worklist.empty()) {
    Value value = worklist.pop_back_val();
    for (OpOperand& use : value.getUses()) {
      Operation* owner = use.getOwner();
      if (!linOp->isProperAncestor(owner)) {
        return failure();
      }
      if (auto inner = dyn_cast<LinOp>(owner)) {
        if (!plan.inlined.insert(inner).second) {
          continue;
        }
        unsigned innerNumDelinearized = getNumDelinearizedResults(inner);
        for (OpResult result : inner->getResults().drop_front(innerNumDelinearized)) {
          if (!isa<LinType>(result.getType())) {
            return failure();
          }
        }
        for (Value operand : inner.getDelinearizedOperands()) {
          if (!isDefinedInside(linOp, operand)) {
            enqueue(operand);
          }
        }
        for (OpResult result : inner->getResults().take_front(innerNumDelinearized)) {
          enqueue(result);
        }
        continue;
      }
      if (auto yield = dyn_cast<scf::YieldOp>(owner)) {
        auto ifOp = dyn_cast<scf::IfOp>(yield->getParentOp());
        if (!ifOp) {
          return failure();
        }
        Value result = ifOp.getResult(use.getOperandNumber());
        if (!plan.converted.contains(result)) {
          plan.ifs.insert(ifOp);
          ifResults.emplace_back(ifOp, use.getOperandNumber());
          enqueue(result);
        }
        continue;
      }
      if (owner == output && use.getOperandNumber() >= numDelinearized) {
        continue;
      }
      return failure();
    }
  }

  // Everything that feeds a converted value must be converted as well.
  for (Operation* op : plan.inlined) {
    for (Value operand : cast<LinOp>(op).getDelinearizedOperands()) {
      if (!plan.converted.contains(operand)) {
        return failure();
      }
    }
  }
  for (auto [ifOp, index] : ifResults) {
    if (ifOp.getElseRegion().empty() || !plan.converted.contains(ifOp.thenYield().getOperand(index)) ||
        !plan.converted.contains(ifOp.elseYield().getOperand(index))) {
      return failure();
    }
  }
  return plan;
}

/// Inlines the body of a nested `lin` op whose delinearized operands have
/// already been replaced by classical values.
static void inlineLinOp(LinOp inner, PatternRewriter& rewriter) {
  rewriter.setInsertionPoint(inner);
  IRMapping mapping;
  mapping.map(inner.getBody().getArguments(), inner.getDelinearizedOperands());
  for (Operation& op : inner.getBody().front().without_terminator()) {
    rewriter.clone(op, mapping);
  }
  OutputOp output = getOutput(inner);
  for (auto [result, value] : llvm::zip(inner->getResults(), output->getOperands())) {
    rewriter.replaceAllUsesWith(result, mapping.lookupOrDefault(value));
  }
  rewriter.eraseOp(inner);
}

/// Rebuilds an `scf.if` whose yields have (partially) been replaced by
/// classical values, with result types to match.
static void retypeIfOp(scf::IfOp ifOp, PatternRewriter& rewriter) {
  rewriter.setInsertionPoint(ifOp);
  auto newIf = scf::IfOp::create(rewriter, ifOp.getLoc(), ifOp.thenYield().getOperandTypes(), ifOp.getCondition(),
                                 /*addThenBlock=*/false, /*addElseBlock=*/false);
  rewriter.inlineRegionBefore(ifOp.getThenRegion(), newIf.getThenRegion(), newIf.getThenRegion().end());
  rewriter.inlineRegionBefore(ifOp.getElseRegion(), newIf.getElseRegion(), newIf.getElseRegion().end());
  rewriter.replaceAllUsesWith(ifOp.getResults(), newIf.getResults());
  rewriter.eraseOp(ifOp);
}

/// Promotes captured linear values of a `lin` op to delinearized operands
/// (see `analyzePromotion`):
///
///   %c, %t1 = lin (%b from %q) {
///     %r = scf.if %b { %x = lin (%tb from %t) {...X...} ; yield %x } else { yield %t }
///     output (%b) carrying (%r)
///   }
/// ->
///   %c, %t1 = lin (%b from %q, %tb from %t) {
///     %r = scf.if %b { ...X(%tb)...; yield %x } else { yield %tb }
///     output (%b, %r)
///   }
///
/// Converted `carrying` operands become linearized results, appended after the
/// existing ones.
struct PromoteCapturedLinValues final : OpRewritePattern<LinOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(LinOp linOp, PatternRewriter& rewriter) const override {
    for (Value capture : getCapturedValues(linOp)) {
      if (!isa<LinType>(capture.getType())) {
        continue;
      }
      FailureOr<PromotionPlan> plan = analyzePromotion(linOp, capture);
      if (succeeded(plan)) {
        promote(linOp, *plan, rewriter);
        return success();
      }
    }
    return failure();
  }

private:
  static void promote(LinOp linOp, const PromotionPlan& plan, PatternRewriter& rewriter) {
    OutputOp output = getOutput(linOp);
    unsigned numDelinearized = output.getDelinearizedResults().size();

    // Result layout: old linearized results, converted `carrying` results,
    // remaining `carrying` results.
    SmallVector<Type> resultTypes = llvm::to_vector(TypeRange(linOp->getResultTypes()).take_front(numDelinearized));
    llvm::SmallBitVector moved(output.getAuxiliaryResults().size());
    for (auto [k, value] : llvm::enumerate(output.getAuxiliaryResults())) {
      if (plan.converted.contains(value)) {
        resultTypes.push_back(value.getType());
        moved.set(k);
      }
    }
    SmallVector<unsigned> auxiliaryIndex;
    unsigned nextMoved = numDelinearized;
    unsigned nextKept = numDelinearized + moved.count();
    for (auto [k, value] : llvm::enumerate(output.getAuxiliaryResults())) {
      if (moved.test(k)) {
        auxiliaryIndex.push_back(nextMoved++);
      } else {
        resultTypes.push_back(value.getType());
        auxiliaryIndex.push_back(nextKept++);
      }
    }

    SmallVector<Value> operands = llvm::to_vector(linOp.getDelinearizedOperands());
    llvm::append_range(operands, plan.promoted);
    rewriter.setInsertionPoint(linOp);
    auto newOp = LinOp::create(rewriter, linOp.getLoc(), resultTypes, operands);
    rewriter.inlineRegionBefore(linOp.getBody(), newOp.getBody(), newOp.getBody().end());
    Block& body = newOp.getBody().front();

    // From here on, converted linear values are replaced by classical ones,
    // and the ops using them are retyped (or inlined) innermost first.
    for (Value value : plan.promoted) {
      BlockArgument arg = body.addArgument(cast<LinType>(value.getType()).getElementType(), value.getLoc());
      rewriter.replaceUsesWithIf(value, arg, [&](OpOperand& use) { return newOp->isProperAncestor(use.getOwner()); });
    }
    SmallVector<Operation*> toRewrite;
    newOp.getBody().walk([&](Operation* op) {
      if (plan.inlined.contains(op) || plan.ifs.contains(op)) {
        toRewrite.push_back(op);
      }
    });
    for (Operation* op : toRewrite) {
      if (auto inner = dyn_cast<LinOp>(op)) {
        inlineLinOp(inner, rewriter);
      } else {
        retypeIfOp(cast<scf::IfOp>(op), rewriter);
      }
    }

    output = cast<OutputOp>(body.getTerminator());
    SmallVector<Value> delinearized = llvm::to_vector(output.getDelinearizedResults());
    SmallVector<Value> auxiliary;
    for (auto [k, value] : llvm::enumerate(output.getAuxiliaryResults())) {
      if (moved.test(k)) {
        delinearized.push_back(value);
      } else {
        auxiliary.push_back(value);
      }
    }
    rewriter.setInsertionPoint(output);
    OutputOp::create(rewriter, output.getLoc(), delinearized, auxiliary);
    rewriter.eraseOp(output);

    for (unsigned i = 0; i < numDelinearized; ++i) {
      rewriter.replaceAllUsesWith(linOp.getResult(i), newOp.getResult(i));
    }
    for (auto [k, index] : llvm::enumerate(auxiliaryIndex)) {
      rewriter.replaceAllUsesWith(linOp.getResult(numDelinearized + k), newOp.getResult(index));
    }
    rewriter.eraseOp(linOp);
  }
};

//===----------------------------------------------------------------------===//
// CancelXOrILeaves
//===----------------------------------------------------------------------===//

/// The `arith` folds only cancel `xor(xor(x, a), a)`, but merged bodies of
/// X and CX gates produce longer chains such as `xor(xor(xor(t, c), 1), c)`.
/// Flattens a tree of single-use `xori` ops (inside a `lin` body) into its
/// leaves, cancels leaves that occur an even number of times, combines the
/// constants, and rebuilds the tree if that made it smaller.
struct CancelXOrILeaves final : OpRewritePattern<arith::XOrIOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(arith::XOrIOp root, PatternRewriter& rewriter) const override {
    auto type = dyn_cast<IntegerType>(root.getType());
    if (!type || !root->getParentOfType<LinOp>()) {
      return failure();
    }

    llvm::MapVector<Value, unsigned> leafCounts;
    unsigned numLeaves = 0;
    APInt constant = APInt::getZero(type.getWidth());
    SmallVector<Value> worklist{root.getRhs(), root.getLhs()};
    while (!worklist.empty()) {
      Value value = worklist.pop_back_val();
      ++numLeaves;
      if (auto inner = value.getDefiningOp<arith::XOrIOp>(); inner && value.hasOneUse()) {
        --numLeaves;
        worklist.push_back(inner.getRhs());
        worklist.push_back(inner.getLhs());
        continue;
      }
      APInt leafConstant;
      if (matchPattern(value, m_ConstantInt(&leafConstant))) {
        constant ^= leafConstant;
        continue;
      }
      ++leafCounts[value];
    }

    SmallVector<Value> remaining;
    for (auto [value, count] : leafCounts) {
      if (count % 2 == 1) {
        remaining.push_back(value);
      }
    }
    if (remaining.size() + (constant.isZero() ? 0 : 1) >= numLeaves) {
      return failure();
    }

    if (!constant.isZero() || remaining.empty()) {
      remaining.push_back(arith::ConstantOp::create(rewriter, root.getLoc(), IntegerAttr::get(type, constant)));
    }
    Value result = remaining.front();
    for (Value value : ArrayRef(remaining).drop_front()) {
      result = arith::XOrIOp::create(rewriter, root.getLoc(), result, value);
    }
    rewriter.replaceOp(root, result);
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Pass
//===----------------------------------------------------------------------===//

struct PrelimHLEPMergeLin final : impl::PrelimHLEPMergeLinBase<PrelimHLEPMergeLin> {
  using PrelimHLEPMergeLinBase::PrelimHLEPMergeLinBase;

protected:
  void runOnOperation() override {
    MLIRContext* context = &getContext();
    RewritePatternSet patterns(context);
    patterns.add<MergeLinChain, CancelXOrILeaves>(context);
    if (promoteCaptures) {
      patterns.add<PromoteCapturedLinValues>(context);
    }
    for (Dialect* dialect : context->getLoadedDialects()) {
      dialect->getCanonicalizationPatterns(patterns);
    }
    for (RegisteredOperationName op : context->getRegisteredOperations()) {
      op.getCanonicalizationPatterns(patterns, context);
    }

    if (failed(applyPatternsGreedily(getOperation(), std::move(patterns)))) {
      getOperation()->emitWarning("prelim-hlep-merge-lin did not converge");
    }
  }
};

} // namespace
} // namespace qcc
