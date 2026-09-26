// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVec.h"
#include "qcc/Dialect/QVec/Transforms/Angles.h"
#include "qcc/Dialect/QVec/Transforms/Passes.h" // IWYU pragma: keep

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include <cstdint>
#include <numbers>
#include <utility>

using namespace mlir;
using namespace qcc::qvec;

namespace {

/// Rewrites one `qvec.single` into `u_zxz(z1, x, z2)` = Rz(z2) Rx(x) Rz(z1), or into `rz` if the gate is diagonal.
/// Every identity below holds up to a global phase.
struct SingleToUZxz final : OpRewritePattern<SingleOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(SingleOp op, PatternRewriter& rewriter) const override {
    constexpr double pi = std::numbers::pi;
    Location loc = op.getLoc();
    const int64_t width = op.getQubitsIn().getType().getNumElements();

    auto splat = [&](double value) { return buildSplatAngleVector(rewriter, loc, width, value); };
    auto uZxz = [&](Value z1, Value x, Value z2) {
      rewriter.replaceOpWithNewOp<SingleOp>(op, SingleGateKind::UZXZ, op.getQubitsIn(), ValueRange{z1, x, z2});
      return success();
    };
    auto rz = [&](double theta) {
      rewriter.replaceOpWithNewOp<SingleOp>(op, SingleGateKind::RZ, op.getQubitsIn(), ValueRange{splat(theta)});
      return success();
    };

    switch (op.getGateKind()) {
    case SingleGateKind::RZ:
    case SingleGateKind::UZXZ:
      return failure(); // Already in the target gate set.
    case SingleGateKind::I:
      return uZxz(splat(0.0), splat(0.0), splat(0.0));
    case SingleGateKind::H:
      return uZxz(splat(pi / 2), splat(pi / 2), splat(pi / 2));
    case SingleGateKind::X:
      return uZxz(splat(0.0), splat(pi), splat(0.0));
    case SingleGateKind::Y:
      return uZxz(splat(-pi / 2), splat(pi), splat(pi / 2));
    case SingleGateKind::RX:
      return uZxz(splat(0.0), op.getParams().front(), splat(0.0));
    case SingleGateKind::RY:
      return uZxz(splat(-pi / 2), op.getParams().front(), splat(pi / 2));
    case SingleGateKind::Z:
      return rz(pi);
    case SingleGateKind::S:
      return rz(pi / 2);
    case SingleGateKind::Sdg:
      return rz(-pi / 2);
    case SingleGateKind::T:
      return rz(pi / 4);
    case SingleGateKind::Tdg:
      return rz(-pi / 4);
    }
    llvm_unreachable("unknown single-qubit gate kind");
  }
};

} // namespace

namespace qcc {

#define GEN_PASS_DEF_QVECTOUZXZ
#include "qcc/Dialect/QVec/Transforms/Passes.h.inc"

namespace {

struct QVecToUZxz final : impl::QVecToUZxzBase<QVecToUZxz> {
  using QVecToUZxzBase::QVecToUZxzBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();
    RewritePatternSet patterns(moduleOp.getContext());
    patterns.add<SingleToUZxz>(moduleOp.getContext());
    if (failed(applyPatternsGreedily(moduleOp, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
