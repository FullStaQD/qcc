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
#include "qcc/Dialect/QVec/Transforms/Zxz.h"

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

#include "llvm/ADT/SmallVector.h"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <utility>

using namespace mlir;
using namespace qcc::qvec;

/// The per-lane ZXZ angles of `op` if it is a `u_zxz` or `rz` with constant angles, nullopt otherwise.
static std::optional<SmallVector<ZxzAngles>> getConstantZxz(SingleOp op) {
  const auto width = static_cast<size_t>(op.getQubitsIn().getType().getNumElements());
  SmallVector<ZxzAngles> lanes(width);

  switch (op.getGateKind()) {
  case SingleGate::RZ: {
    std::optional<SmallVector<double>> theta = getConstantAngles(op.getParams().front());
    if (!theta) {
      return std::nullopt;
    }
    for (size_t lane = 0; lane < width; ++lane) {
      lanes[lane].z1 = (*theta)[lane];
    }
    return lanes;
  }
  case SingleGate::UZXZ: {
    std::optional<SmallVector<double>> z1 = getConstantAngles(op.getParams()[zxz::z1]);
    std::optional<SmallVector<double>> x = getConstantAngles(op.getParams()[zxz::x]);
    std::optional<SmallVector<double>> z2 = getConstantAngles(op.getParams()[zxz::z2]);
    if (!z1 || !x || !z2) {
      return std::nullopt;
    }
    for (size_t lane = 0; lane < width; ++lane) {
      lanes[lane] = ZxzAngles{.z1 = (*z1)[lane], .x = (*x)[lane], .z2 = (*z2)[lane]};
    }
    return lanes;
  }
  default:
    return std::nullopt;
  }
}

namespace {

/// Fuses a `u_zxz` / `rz` into the `u_zxz` / `rz` that feeds it, if that one has no other user.
struct FuseZxz final : OpRewritePattern<SingleOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(SingleOp second, PatternRewriter& rewriter) const override {
    auto first = second.getQubitsIn().getDefiningOp<SingleOp>();
    if (!first || !first.getQubitsOut().hasOneUse()) {
      return failure();
    }
    std::optional<SmallVector<ZxzAngles>> firstLanes = getConstantZxz(first);
    std::optional<SmallVector<ZxzAngles>> secondLanes = getConstantZxz(second);
    if (!firstLanes || !secondLanes) {
      return failure();
    }

    Location loc = second.getLoc();
    const size_t width = firstLanes->size();
    if (first.getGateKind() == SingleGate::RZ && second.getGateKind() == SingleGate::RZ) {
      SmallVector<double> theta(width);
      for (size_t lane = 0; lane < width; ++lane) {
        theta[lane] = normalizeAngle((*firstLanes)[lane].z1 + (*secondLanes)[lane].z1);
      }
      rewriter.replaceOpWithNewOp<SingleOp>(second, SingleGate::RZ, first.getQubitsIn(),
                                            ValueRange{buildAngleVector(rewriter, loc, theta)});
    } else {
      SmallVector<double> z1(width);
      SmallVector<double> x(width);
      SmallVector<double> z2(width);
      for (size_t lane = 0; lane < width; ++lane) {
        const ZxzAngles fused = fuseZxz((*firstLanes)[lane], (*secondLanes)[lane]);
        z1[lane] = fused.z1;
        x[lane] = fused.x;
        z2[lane] = fused.z2;
      }
      rewriter.replaceOpWithNewOp<SingleOp>(second, SingleGate::UZXZ, first.getQubitsIn(),
                                            ValueRange{
                                                buildAngleVector(rewriter, loc, z1),
                                                buildAngleVector(rewriter, loc, x),
                                                buildAngleVector(rewriter, loc, z2),
                                            });
    }
    rewriter.eraseOp(first);
    return success();
  }
};

} // namespace

namespace qcc {

#define GEN_PASS_DEF_QVECFUSEZXZ
#include "qcc/Dialect/QVec/Transforms/Passes.h.inc"

namespace {

struct QVecFuseZxz final : impl::QVecFuseZxzBase<QVecFuseZxz> {
  using QVecFuseZxzBase::QVecFuseZxzBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();
    RewritePatternSet patterns(moduleOp.getContext());
    patterns.add<FuseZxz>(moduleOp.getContext());
    if (failed(applyPatternsGreedily(moduleOp, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
