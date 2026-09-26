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

/// Rewrites one `qvec.pair` of any kind but `rzz` into `rzz` plus single-qubit gates. Every identity below holds up to
/// a global phase; the single-qubit gates come out as `h`, `s`, `sdg`, `rz` and are `qvec-to-u-zxz`'s business.
struct PairToRZZ final : OpRewritePattern<PairOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(PairOp op, PatternRewriter& rewriter) const override {
    constexpr double pi = std::numbers::pi;
    Location loc = op.getLoc();
    const int64_t width = op.getLhsIn().getType().getNumElements();

    auto single = [&](SingleGateKind kind, Value qubits, Value theta = {}) -> Value {
      return SingleOp::create(rewriter, loc, kind, qubits, theta ? ValueRange{theta} : ValueRange{}).getQubitsOut();
    };
    auto pair = [&](PairGateKind kind, Value first, Value second, Value theta = {}) -> std::pair<Value, Value> {
      auto pairOp = PairOp::create(rewriter, loc, kind, first, second, theta ? ValueRange{theta} : ValueRange{});
      return {pairOp.getLhsOut(), pairOp.getRhsOut()};
    };
    auto splat = [&](double value) { return buildSplatAngleVector(rewriter, loc, width, value); };

    Value lhs = op.getLhsIn();
    Value rhs = op.getRhsIn();
    switch (op.getGateKind()) {
    case PairGateKind::RZZ:
      return failure(); // Already there.
    case PairGateKind::CZ: {
      // cz = (rz(-pi/2) (x) rz(-pi/2)) * rzz(pi/2)
      std::tie(lhs, rhs) = pair(PairGateKind::RZZ, lhs, rhs, splat(pi / 2));
      Value minusQuarter = splat(-pi / 2);
      lhs = single(SingleGateKind::RZ, lhs, minusQuarter);
      rhs = single(SingleGateKind::RZ, rhs, minusQuarter);
      break;
    }
    case PairGateKind::CX: {
      // cx = h_t * cz * h_t
      rhs = single(SingleGateKind::H, rhs);
      std::tie(lhs, rhs) = pair(PairGateKind::CZ, lhs, rhs);
      rhs = single(SingleGateKind::H, rhs);
      break;
    }
    case PairGateKind::CY: {
      // cy = s_t * cx * sdg_t
      rhs = single(SingleGateKind::Sdg, rhs);
      std::tie(lhs, rhs) = pair(PairGateKind::CX, lhs, rhs);
      rhs = single(SingleGateKind::S, rhs);
      break;
    }
    case PairGateKind::CP: {
      // cp(t) = (rz(t/2) (x) rz(t/2)) * rzz(-t/2)
      Value theta = op.getParams().front();
      std::tie(lhs, rhs) = pair(PairGateKind::RZZ, lhs, rhs, scaleAngles(rewriter, loc, theta, -0.5));
      Value half = scaleAngles(rewriter, loc, theta, 0.5);
      lhs = single(SingleGateKind::RZ, lhs, half);
      rhs = single(SingleGateKind::RZ, rhs, half);
      break;
    }
    case PairGateKind::iSWAP: {
      // iswap = swap * cz * (s (x) s), with swap = cx(a, b) * cx(b, a) * cx(a, b)
      lhs = single(SingleGateKind::S, lhs);
      rhs = single(SingleGateKind::S, rhs);
      std::tie(lhs, rhs) = pair(PairGateKind::CZ, lhs, rhs);
      std::tie(lhs, rhs) = pair(PairGateKind::CX, lhs, rhs);
      std::tie(rhs, lhs) = pair(PairGateKind::CX, rhs, lhs);
      std::tie(lhs, rhs) = pair(PairGateKind::CX, lhs, rhs);
      break;
    }
    }

    rewriter.replaceOp(op, ValueRange{lhs, rhs});
    return success();
  }
};

} // namespace

namespace qcc {

#define GEN_PASS_DEF_QVECTORZZ
#include "qcc/Dialect/QVec/Transforms/Passes.h.inc"

namespace {

struct QVecToRZZ final : impl::QVecToRZZBase<QVecToRZZ> {
  using QVecToRZZBase::QVecToRZZBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();
    RewritePatternSet patterns(moduleOp.getContext());
    patterns.add<PairToRZZ>(moduleOp.getContext());
    if (failed(applyPatternsGreedily(moduleOp, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
