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

using namespace mlir;

namespace qcc::magic {

#define GEN_PASS_DEF_MAGICPADTIMING
#include "qcc/Dialect/Magic/Transforms/Passes.h.inc"

/// Lets `chain` idle for `ticks`: every active ion inactive, one delay, the activations back. Inserted at the
/// builder's insertion point; the uses of `chain` move to the padded value.
static void pad(OpBuilder& builder, Value chain, Ticks ticks) {
  const Location loc = chain.getLoc();
  const SmallVector<int64_t> active = cast<IonChainType>(chain.getType()).getActiveIons();

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
  for (const TimingSegment& segment : getTimingSegments(block)) {
    const Ticks max = segment.getMaxTicks();
    for (const auto& [trap, entry] : segment.traps) {
      if (entry.ticks == max) {
        continue;
      }
      // At the end of the segment: before the shuttle that closes it, or before the measurement (or wherever the
      // chain ends) for the last one.
      OpBuilder builder(block.getParentOp()->getContext());
      if (segment.end != nullptr) {
        builder.setInsertionPoint(segment.end);
      } else if (!entry.chain.use_empty()) {
        builder.setInsertionPoint(*entry.chain.user_begin());
      } else {
        builder.setInsertionPointAfterValue(entry.chain);
      }
      pad(builder, entry.chain, max - entry.ticks);
    }
  }
}

namespace {

struct MagicPadTiming final : impl::MagicPadTimingBase<MagicPadTiming> {
  using MagicPadTimingBase::MagicPadTimingBase;

protected:
  void runOnOperation() override {
    // The magic ops of a program sit directly in the single block of its function (op verifier).
    func::FuncOp func = getOperation();
    if (!func.isExternal()) {
      padBlock(func.front());
    }
  }
};

} // namespace
} // namespace qcc::magic
