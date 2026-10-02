// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/Device/MagicDevice.h"
#include "qcc/Dialect/Magic/IR/Magic.h"
#include "qcc/Dialect/Magic/Transforms/Passes.h" // IWYU pragma: keep
#include "qcc/Dialect/Magic/Transforms/Timing.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <cstdlib>

using namespace mlir;

namespace qcc::magic {

#define GEN_PASS_DEF_MAGICPADTIMING
#include "qcc/Dialect/Magic/Transforms/Passes.h.inc"

static void pad(OpBuilder& builder, TypedValue<IonChainType> chain, Ticks ticks) {
  const Location loc = chain.getLoc();
  const SmallVector<int64_t> active = chain.getType().getActiveIons();

  Value padded = chain;
  Operation* first = nullptr;

  if (!active.empty()) {
    first = RecodeOp::create(builder, loc, padded, active);
    padded = first->getResult(0);
  }

  auto delay = DelayOp::create(builder, loc, padded.getType(), padded, builder.getI64IntegerAttr(ticks));
  if (first == nullptr) {
    first = delay;
  }

  padded = delay;
  if (!active.empty()) {
    padded = RecodeOp::create(builder, loc, padded, active);
  }

  chain.replaceAllUsesExcept(padded, first);
}

static void padBlock(Block& block) {
  forEachUnbalancedShuttle(block, [](ShuttleOp shuttle, Ticks fromTicks, Ticks toTicks) {
    // The trap that is faster waits right before the shuttle.
    OpBuilder builder(shuttle);
    pad(builder, fromTicks < toTicks ? shuttle.getFromIn() : shuttle.getToIn(), std::abs(toTicks - fromTicks));
  });
}

namespace {

struct MagicPadTiming final : impl::MagicPadTimingBase<MagicPadTiming> {
  using MagicPadTimingBase::MagicPadTimingBase;

protected:
  void runOnOperation() override {
    func::FuncOp func = getOperation();
    if (!func.isExternal()) {
      padBlock(func.front());
    }
  }
};

} // namespace
} // namespace qcc::magic
