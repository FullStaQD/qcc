// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QCirc/IR/QCirc.h"
#include "qcc/Dialect/QCirc/Transforms/Angles.h"
#include "qcc/Dialect/QCirc/Transforms/Passes.h" // IWYU pragma: keep

#include "mlir/Dialect/Arith/IR/Arith.h"  // IWYU pragma: keep
#include "mlir/Dialect/Func/IR/FuncOps.h" // IWYU pragma: keep
#include "mlir/IR/Location.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

#include "llvm/Support/ErrorHandling.h"

#include <numbers>
#include <utility>

using namespace mlir;
using namespace qcc::qcirc;
using qcc::SingleGateKind;

namespace {

/// Rewrites one `qcirc.single` into `u_zxz(z1, x, z2)` = Rz(z2) Rx(x) Rz(z1), or into `rz` if the gate is diagonal.
/// Every identity below holds up to a global phase.
struct SingleToUZXZ final : OpRewritePattern<SingleOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(SingleOp op, PatternRewriter& rewriter) const override {
    constexpr double pi = std::numbers::pi;
    Location loc = op.getLoc();

    auto angle = [&](double value) { return buildAngle(rewriter, loc, value); };

    auto uZXZ = [&](Value z1, Value x, Value z2) {
      rewriter.replaceOpWithNewOp<SingleOp>(op, SingleGateKind::UZXZ, op.getQubitIn(), ValueRange{z1, x, z2});
      return success();
    };

    // rx(theta) = u_zxz(0, theta, 0)
    auto xRotation = [&](Value theta) {
      Value zero = angle(0.0);
      return uZXZ(zero, theta, zero);
    };

    auto rz = [&](double theta) {
      rewriter.replaceOpWithNewOp<SingleOp>(op, SingleGateKind::RZ, op.getQubitIn(), ValueRange{angle(theta)});
      return success();
    };

    switch (op.getGateKind()) {
    case SingleGateKind::RZ:
    case SingleGateKind::UZXZ:
      return failure(); // Already in the target gate set.
    case SingleGateKind::H: {
      Value quarter = angle(pi / 2);
      return uZXZ(quarter, quarter, quarter);
    }
    case SingleGateKind::X:
      return xRotation(angle(pi));
    case SingleGateKind::Y: {
      // Build angles in named locals: argument evaluation order, and thus constant order, is compiler-dependent.
      Value z1 = angle(-pi / 2);
      Value x = angle(pi);
      Value z2 = angle(pi / 2);
      return uZXZ(z1, x, z2);
    }
    case SingleGateKind::SX:
      return xRotation(angle(pi / 2));
    case SingleGateKind::SXdg:
      return xRotation(angle(-pi / 2));
    case SingleGateKind::RX:
      return xRotation(op.getParams().front());
    case SingleGateKind::RY: {
      Value z1 = angle(-pi / 2);
      Value z2 = angle(pi / 2);
      return uZXZ(z1, op.getParams().front(), z2);
    }
    case SingleGateKind::UZYZ: {
      // u_zyz(z1, y, z2) = u_zxz(z1 - pi/2, y, z2 + pi/2).
      ValueRange params = op.getParams();
      Value z1 = offsetAngle(rewriter, loc, params[qcc::zxz::z1], -pi / 2);
      Value z2 = offsetAngle(rewriter, loc, params[qcc::zxz::z2], pi / 2);
      return uZXZ(z1, params[qcc::zxz::x], z2);
    }
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

#define GEN_PASS_DEF_QCIRCTOUZXZ
#include "qcc/Dialect/QCirc/Transforms/Passes.h.inc"

namespace {

struct QCircToUZXZ final : impl::QCircToUZXZBase<QCircToUZXZ> {
  using QCircToUZXZBase::QCircToUZXZBase;

protected:
  void runOnOperation() override {
    RewritePatternSet patterns(&getContext());
    patterns.add<SingleToUZXZ>(&getContext());
    walkAndApplyPatterns(getOperation(), std::move(patterns));
  }
};

} // namespace
} // namespace qcc
