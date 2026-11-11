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
#include "qcc/Dialect/Utils/RotationUtils.h"

#include "mlir/Dialect/Arith/IR/Arith.h"  // IWYU pragma: keep
#include "mlir/Dialect/Func/IR/FuncOps.h" // IWYU pragma: keep
#include "mlir/IR/Location.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>
#include <variant>

using namespace mlir;
using namespace qcc::qcirc;

namespace {

/// A rotation that `qcirc-fuse-zxz` can fuse: the angle of an `rz` or the angles of a `u_zxz`.
using Rotation = std::variant<double, qcc::ZXZAngles>;

} // namespace

/// The rotation `op` applies if it is an `rz` or a `u_zxz` with constant angles, nullopt otherwise.
static std::optional<Rotation> getConstantRotation(SingleOp op) {
  ValueRange params = op.getParams();
  switch (op.getGateKind()) {
  case qcc::SingleGateKind::RZ:
    return getConstantAngle(params.front());
  case qcc::SingleGateKind::UZXZ: {
    std::optional<double> z1 = getConstantAngle(params[qcc::zxz::z1]);
    std::optional<double> x = getConstantAngle(params[qcc::zxz::x]);
    std::optional<double> z2 = getConstantAngle(params[qcc::zxz::z2]);
    if (!z1 || !x || !z2) {
      return std::nullopt;
    }
    return qcc::ZXZAngles{.z1 = *z1, .x = *x, .z2 = *z2};
  }
  default:
    return std::nullopt;
  }
}

/// The rotation that applies `first` and then `second`. Fusing with an `rz` is exact (see `fuseZXZ`).
static Rotation fuse(const Rotation& first, const Rotation& second) {
  return std::visit(llvm::makeVisitor([](double a, double b) -> Rotation { return qcc::normalizeAngle(a + b); },
                                      [](const auto& a, const auto& b) -> Rotation { return qcc::fuseZXZ(a, b); }),
                    first, second);
}

/// Erases the ops that define `angles` if nothing uses them any more.
static void eraseUnusedAngles(RewriterBase& rewriter, ValueRange angles) {
  llvm::SmallSetVector<Operation*, 6> definingOps;
  for (Value angle : angles) {
    if (Operation* definingOp = angle.getDefiningOp()) {
      definingOps.insert(definingOp);
    }
  }
  for (Operation* definingOp : definingOps) {
    if (isOpTriviallyDead(definingOp)) {
      rewriter.eraseOp(definingOp);
    }
  }
}

/// Fuses `second`, a `u_zxz` / `rz`, into the `u_zxz` / `rz` that feeds it, if both have constant angles. As a qubit
/// has at most one use, `second` is the only user of that gate.
static void fuseIntoProducer(RewriterBase& rewriter, SingleOp second) {
  auto first = second.getQubitIn().getDefiningOp<SingleOp>();
  if (!first) {
    return;
  }
  std::optional<Rotation> firstRotation = getConstantRotation(first);
  std::optional<Rotation> secondRotation = getConstantRotation(second);
  if (!firstRotation || !secondRotation) {
    return;
  }

  SmallVector<Value> oldAngles(first.getParams());
  llvm::append_range(oldAngles, second.getParams());
  Location loc = second.getLoc();
  rewriter.setInsertionPoint(second);
  auto angle = [&](double value) { return buildAngle(rewriter, loc, value); };
  const Rotation fused = fuse(*firstRotation, *secondRotation);
  if (const auto* theta = std::get_if<double>(&fused)) {
    rewriter.replaceOpWithNewOp<SingleOp>(second, qcc::SingleGateKind::RZ, first.getQubitIn(),
                                          ValueRange{angle(*theta)});
  } else {
    const auto& zxz = std::get<qcc::ZXZAngles>(fused);
    rewriter.replaceOpWithNewOp<SingleOp>(second, qcc::SingleGateKind::UZXZ, first.getQubitIn(),
                                          ValueRange{angle(zxz.z1), angle(zxz.x), angle(zxz.z2)});
  }
  rewriter.eraseOp(first);
  eraseUnusedAngles(rewriter, oldAngles);
}

namespace qcc {

#define GEN_PASS_DEF_QCIRCFUSEZXZ
#include "qcc/Dialect/QCirc/Transforms/Passes.h.inc"

namespace {

struct QCircFuseZXZ final : impl::QCircFuseZXZBase<QCircFuseZXZ> {
  using QCircFuseZXZBase::QCircFuseZXZBase;

protected:
  void runOnOperation() override {
    // A plain walk, as it may erase the ops it visited already; the greedy driver would also erase the gates whose
    // qubits nothing observes. One walk in program order suffices: the fused gate is the first one of the next pair.
    IRRewriter rewriter(&getContext());
    getOperation().walk([&](SingleOp op) { fuseIntoProducer(rewriter, op); });
  }
};

} // namespace
} // namespace qcc
