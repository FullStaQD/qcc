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
#include "mlir/IR/Builders.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

#include <numbers>
#include <utility>

using namespace mlir;
using namespace qcc::qcirc;
using qcc::PairGateKind;
using qcc::SingleGateKind;

/// Applies the single-qubit gate `kind` with the angle `angle` (if it takes one) to `qubit`, which is updated.
static void applySingle(OpBuilder& builder, Location loc, SingleGateKind kind, Value& qubit, Value angle = {}) {
  qubit = SingleOp::create(builder, loc, kind, qubit, angle ? ValueRange{angle} : ValueRange{}).getQubitOut();
}

/// Applies the pair gate `kind` with the angle `theta` (if it takes one) to `lhs` and `rhs`, which are updated: emits
/// `rzz` and single-qubit gates at the insertion point of `builder`. Every identity below holds up to a global phase.
static void applyPair(OpBuilder& builder, Location loc, PairGateKind kind, Value& lhs, Value& rhs, Value theta = {}) {
  constexpr double pi = std::numbers::pi;

  switch (kind) {
  case PairGateKind::RZZ: {
    auto pairOp = PairOp::create(builder, loc, kind, lhs, rhs, theta);
    lhs = pairOp.getLhsOut();
    rhs = pairOp.getRhsOut();
    break;
  }
  case PairGateKind::CZ: {
    // cz = (rz(-pi/2) (x) rz(-pi/2)) * rzz(pi/2)
    applyPair(builder, loc, PairGateKind::RZZ, lhs, rhs, buildAngle(builder, loc, pi / 2));
    Value minusQuarter = buildAngle(builder, loc, -pi / 2);
    applySingle(builder, loc, SingleGateKind::RZ, lhs, minusQuarter);
    applySingle(builder, loc, SingleGateKind::RZ, rhs, minusQuarter);
    break;
  }
  case PairGateKind::CX:
    // cx = h_t * cz * h_t
    applySingle(builder, loc, SingleGateKind::H, rhs);
    applyPair(builder, loc, PairGateKind::CZ, lhs, rhs);
    applySingle(builder, loc, SingleGateKind::H, rhs);
    break;
  case PairGateKind::CY:
    // cy = s_t * cx * sdg_t
    applySingle(builder, loc, SingleGateKind::Sdg, rhs);
    applyPair(builder, loc, PairGateKind::CX, lhs, rhs);
    applySingle(builder, loc, SingleGateKind::S, rhs);
    break;
  case PairGateKind::CP: {
    // cp(t) = (rz(t/2) (x) rz(t/2)) * rzz(-t/2)
    applyPair(builder, loc, PairGateKind::RZZ, lhs, rhs, scaleAngle(builder, loc, theta, -0.5));
    Value half = scaleAngle(builder, loc, theta, 0.5);
    applySingle(builder, loc, SingleGateKind::RZ, lhs, half);
    applySingle(builder, loc, SingleGateKind::RZ, rhs, half);
    break;
  }
  case PairGateKind::CRZ:
    // crz(t) = (1 (x) rz(t/2)) * rzz(-t/2)
    applyPair(builder, loc, PairGateKind::RZZ, lhs, rhs, scaleAngle(builder, loc, theta, -0.5));
    applySingle(builder, loc, SingleGateKind::RZ, rhs, scaleAngle(builder, loc, theta, 0.5));
    break;
  case PairGateKind::RXX:
    // rxx(t) = (h (x) h) * rzz(t) * (h (x) h)
    applySingle(builder, loc, SingleGateKind::H, lhs);
    applySingle(builder, loc, SingleGateKind::H, rhs);
    applyPair(builder, loc, PairGateKind::RZZ, lhs, rhs, theta);
    applySingle(builder, loc, SingleGateKind::H, lhs);
    applySingle(builder, loc, SingleGateKind::H, rhs);
    break;
  case PairGateKind::RYY: {
    // ryy(t) = (rx(-pi/2) (x) rx(-pi/2)) * rzz(t) * (rx(pi/2) (x) rx(pi/2))
    Value quarter = buildAngle(builder, loc, pi / 2);
    applySingle(builder, loc, SingleGateKind::RX, lhs, quarter);
    applySingle(builder, loc, SingleGateKind::RX, rhs, quarter);
    applyPair(builder, loc, PairGateKind::RZZ, lhs, rhs, theta);
    Value minusQuarter = buildAngle(builder, loc, -pi / 2);
    applySingle(builder, loc, SingleGateKind::RX, lhs, minusQuarter);
    applySingle(builder, loc, SingleGateKind::RX, rhs, minusQuarter);
    break;
  }
  case PairGateKind::SWAP:
    // swap = cx(a, b) * cx(b, a) * cx(a, b); it does not exchange the lanes, only the states.
    applyPair(builder, loc, PairGateKind::CX, lhs, rhs);
    applyPair(builder, loc, PairGateKind::CX, rhs, lhs); // NOLINT(readability-suspicious-call-argument)
    applyPair(builder, loc, PairGateKind::CX, lhs, rhs);
    break;
  case PairGateKind::iSWAP:
    // iswap = swap * cz * (s (x) s)
    applySingle(builder, loc, SingleGateKind::S, lhs);
    applySingle(builder, loc, SingleGateKind::S, rhs);
    applyPair(builder, loc, PairGateKind::CZ, lhs, rhs);
    applyPair(builder, loc, PairGateKind::SWAP, lhs, rhs);
    break;
  }
}

namespace {

/// Rewrites one `qcirc.pair` of any kind other than `rzz` into `rzz` plus single-qubit gates.
struct PairToRZZ final : OpRewritePattern<PairOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(PairOp op, PatternRewriter& rewriter) const override {
    if (op.getGateKind() == PairGateKind::RZZ) {
      return failure(); // Already there.
    }
    Value lhs = op.getLhsIn();
    Value rhs = op.getRhsIn();
    Value theta = op.getParams().empty() ? Value() : op.getParams().front();
    applyPair(rewriter, op.getLoc(), op.getGateKind(), lhs, rhs, theta);
    rewriter.replaceOp(op, ValueRange{lhs, rhs});
    return success();
  }
};

} // namespace

namespace qcc {

#define GEN_PASS_DEF_QCIRCTORZZ
#include "qcc/Dialect/QCirc/Transforms/Passes.h.inc"

namespace {

struct QCircToRZZ final : impl::QCircToRZZBase<QCircToRZZ> {
  using QCircToRZZBase::QCircToRZZBase;

protected:
  void runOnOperation() override {
    RewritePatternSet patterns(&getContext());
    patterns.add<PairToRZZ>(&getContext());
    walkAndApplyPatterns(getOperation(), std::move(patterns));
  }
};

} // namespace
} // namespace qcc
