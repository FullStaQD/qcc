//===- WhileToFor.cpp - scf.while to scf.for pass ------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "qcc/Conversion/AffineRaise/AffineRaise.h" // IWYU pragma: keep

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Types.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

using namespace mlir;

namespace qcc {

#define GEN_PASS_DEF_WHILETOFOR
#include "qcc/Conversion/AffineRaise/AffineRaise.h.inc"

namespace {
struct ConvertWhileSLEToSLT : public OpRewritePattern<scf::WhileOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(scf::WhileOp loop, PatternRewriter& rewriter) const override {
    Block* beforeBody = loop.getBeforeBody();
    if (!llvm::hasSingleElement(beforeBody->without_terminator())) {
      return failure();
    }

    scf::ConditionOp beforeTerm = loop.getConditionOp();
    auto cmp = beforeTerm.getCondition().getDefiningOp<arith::CmpIOp>();
    if (!cmp || cmp.getPredicate() != arith::CmpIPredicate::sle) {
      return failure();
    }

    if (cmp->getBlock() != beforeBody || beforeTerm.getCondition() != cmp->getResult(0)) {
      return failure();
    }

    auto arg = dyn_cast<BlockArgument>(cmp.getLhs());
    if (!arg || arg.getOwner() != beforeBody) {
      return failure();
    }

    Value ub = cmp.getRhs();

    Location loc = cmp.getLoc();
    OpBuilder::InsertionGuard guard(rewriter);
    rewriter.setInsertionPoint(cmp);

    Value one;
    if (isa<IndexType>(ub.getType())) {
      one = arith::ConstantIndexOp::create(rewriter, loc, 1);
    } else if (auto intTy = dyn_cast<IntegerType>(ub.getType())) {
      one = arith::ConstantIntOp::create(rewriter, loc, 1, intTy.getWidth());
    } else {
      return failure();
    }

    auto newUb = arith::AddIOp::create(rewriter, loc, ub, one).getResult();
    auto newCmp = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::slt, cmp.getLhs(), newUb);
    rewriter.replaceOp(cmp, newCmp.getResult());
    return success();
  }
};
} // namespace

namespace {
struct WhileToFor final : public impl::WhileToForBase<WhileToFor> {
  using impl::WhileToForBase<WhileToFor>::WhileToForBase;

protected:
  void runOnOperation() override {
    RewritePatternSet patterns(&getContext());
    patterns.add<ConvertWhileSLEToSLT>(&getContext());
    mlir::scf::populateUpliftWhileToForPatterns(patterns);
    if (failed(applyPatternsGreedily(getOperation(), std::move(patterns)))) {
      signalPassFailure();
    }
  }
};
} // namespace

} // namespace qcc
