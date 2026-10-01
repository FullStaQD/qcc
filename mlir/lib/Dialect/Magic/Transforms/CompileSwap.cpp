// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/IR/Magic.h"
#include "qcc/Dialect/Magic/Transforms/Passes.h" // IWYU pragma: keep

#include "mlir/IR/Builders.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Value.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <numbers>

using namespace mlir;

namespace qcc::magic {

#define GEN_PASS_DEF_MAGICCOMPILESWAP
#include "qcc/Dialect/Magic/Transforms/Passes.h.inc"

constexpr double halfPi = std::numbers::pi / 2.0;

/// Replaces `op` by `cx(a, b) cx(b, a) cx(a, b)`, up to a global phase.
static LogicalResult compileSwap(SwapOp op) {
  const IonChainType type = op.getChainIn().getType();
  const int64_t ionA = op.getIons()[0];
  const int64_t ionB = op.getIons()[1];
  if (!type.isActive(ionA) || !type.isActive(ionB)) {
    return op.emitOpError() << "expects both ions to be active";
  }

  OpBuilder builder(op);
  const Location loc = op.getLoc();
  Value chain = op.getChainIn();

  // h = Rz(pi/2) Rx(pi/2) Rz(pi/2) up to a global phase.
  auto hadamard = [&](int64_t ion) {
    auto angle = builder.getF64ArrayAttr({halfPi});
    chain = ZXZOp::create(builder, loc, chain.getType(), chain, ArrayRef<int64_t>{ion}, angle, angle, angle);
  };

  // cz = rzz(pi/2) followed by rz(-pi/2) on both ions, up to a global phase.
  auto cz = [&](int64_t ionCtrl, int64_t ionTgt) {
    chain = ActiveZZOp::create(builder, loc, chain, ionCtrl, ionTgt, halfPi);
    chain = RZOp::create(builder, loc, chain.getType(), chain, ArrayRef<int64_t>{ionCtrl, ionTgt},
                         builder.getF64ArrayAttr({-halfPi, -halfPi}));
  };

  // cx(control, target) = h(target) cz h(target).
  auto cx = [&](int64_t ionCtrl, int64_t ionTgt) {
    hadamard(ionTgt);
    cz(ionCtrl, ionTgt);
    hadamard(ionTgt);
  };

  cx(ionA, ionB);
  cx(ionB, ionA);
  cx(ionA, ionB);

  op.getChainOut().replaceAllUsesWith(chain);
  op.erase();
  return success();
}

namespace {

struct MagicCompileSwap final : impl::MagicCompileSwapBase<MagicCompileSwap> {
  using MagicCompileSwapBase::MagicCompileSwapBase;

protected:
  void runOnOperation() override {
    SmallVector<SwapOp> ops;
    getOperation().walk([&](SwapOp op) { ops.push_back(op); });
    for (SwapOp op : ops) {
      if (failed(compileSwap(op))) {
        return signalPassFailure();
      }
    }
  }
};

} // namespace
} // namespace qcc::magic
