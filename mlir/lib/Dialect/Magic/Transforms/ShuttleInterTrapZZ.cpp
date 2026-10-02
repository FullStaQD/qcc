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

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Value.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <utility>

using namespace mlir;

namespace qcc::magic {

#define GEN_PASS_DEF_MAGICSHUTTLEINTERTRAPZZ
#include "qcc/Dialect/Magic/Transforms/Passes.h.inc"

/// The number of ions `chain` can still take in.
static int64_t freeSlots(IonChainType chain, const MagicDevice& device) {
  return static_cast<int64_t>(device.capacity(static_cast<TrapId>(chain.getTrap()))) -
         static_cast<int64_t>(chain.getNumIons());
}

/// Shuttles the `count` front ions of the `from` chain to the `to` chain, applies `rzz(angle)` between `fromIon` (then
/// at the front of `to`) and `toIon` there and shuttles the ions back, which restores both chains. An inactive
/// `fromIon` or `toIon` is recoded for the duration. Returns the new (from, to).
static std::pair<TypedValue<IonChainType>, TypedValue<IonChainType>>
buildZZViaShuttle(OpBuilder& builder, Location loc, TypedValue<IonChainType> from, TypedValue<IonChainType> to,
                  int64_t count, int64_t fromIon, int64_t toIon, double angle) {
  // The coupling acts between active ions only.
  const bool recodeFrom = !from.getType().isActive(fromIon);
  const bool recodeTo = !to.getType().isActive(toIon);
  if (recodeFrom) {
    from = RecodeOp::create(builder, loc, from, {fromIon});
  }
  if (recodeTo) {
    to = RecodeOp::create(builder, loc, to, {toIon});
  }

  for (int64_t k = 0; k < count; ++k) {
    auto shuttle = ShuttleOp::create(builder, loc, from, to);
    from = shuttle.getFromOut();
    to = shuttle.getToOut();
  }
  to = ActiveZZOp::create(builder, loc, to, fromIon, toIon, angle);
  // The ions arrived in reverse order; moving them back front to front reverses them again.
  for (int64_t k = 0; k < count; ++k) {
    auto shuttle = ShuttleOp::create(builder, loc, to, from);
    to = shuttle.getFromOut();
    from = shuttle.getToOut();
  }

  if (recodeTo) {
    to = RecodeOp::create(builder, loc, to, {toIon});
  }
  if (recodeFrom) {
    from = RecodeOp::create(builder, loc, from, {fromIon});
  }
  return {from, to};
}

/// Like `buildZZViaShuttle`, but moves only the front ion of `from`: `fromIon` is swapped to the front first and back
/// afterwards. Needs a single free slot in `to`. The swaps are logical, so it is the front ion that has to be active
/// for the coupling, not `fromIon`.
static std::pair<TypedValue<IonChainType>, TypedValue<IonChainType>>
buildZZViaSwapAndShuttle(OpBuilder& builder, Location loc, TypedValue<IonChainType> from, TypedValue<IonChainType> to,
                         int64_t fromIon, int64_t toIon, double angle) {
  const int64_t front = from.getType().getSlots().front().ion;
  auto swap = [&](TypedValue<IonChainType> chain) -> TypedValue<IonChainType> {
    if (front == fromIon) {
      return chain;
    }
    return SwapOp::create(builder, loc, chain, fromIon, front);
  };
  from = swap(from);
  std::tie(from, to) = buildZZViaShuttle(builder, loc, from, to, /*count=*/1, front, toIon, angle);
  from = swap(from);
  return {from, to};
}

static LogicalResult lowerInterTrapZZ(InterTrapZZOp op, const MagicDevice& device) {
  const IonChainType a = op.getAIn().getType();
  const IonChainType b = op.getBIn().getType();
  const int64_t ionA = op.getIons()[0];
  const int64_t ionB = op.getIons()[1];

  const int64_t moveA = a.getPosition(ionA) + 1; // ions to move for the shuttle variant that moves `ionA` to `b`
  const int64_t moveB = b.getPosition(ionB) + 1;
  const int64_t freeA = freeSlots(a, device);
  const int64_t freeB = freeSlots(b, device);
  const double angle = op.getAngle().convertToDouble();

  OpBuilder builder(op);
  const Location loc = op.getLoc();
  TypedValue<IonChainType> chainA = op.getAIn();
  TypedValue<IonChainType> chainB = op.getBIn();

  // A shuttle variant fits if the other trap has room for all ions that move; of two that fit, the cheaper one wins.
  // Otherwise the swap-and-shuttle variant as a fallback, which needs one free slot.
  const bool fitsA = moveA <= freeB;
  const bool fitsB = moveB <= freeA;
  const bool preferA = !fitsB || moveA <= moveB;
  if (fitsA && preferA) {
    std::tie(chainA, chainB) = buildZZViaShuttle(builder, loc, chainA, chainB, moveA, ionA, ionB, angle);
  } else if (fitsB) {
    std::tie(chainB, chainA) = buildZZViaShuttle(builder, loc, chainB, chainA, moveB, ionB, ionA, angle);
  } else if (freeB > 0) {
    std::tie(chainA, chainB) = buildZZViaSwapAndShuttle(builder, loc, chainA, chainB, ionA, ionB, angle);
  } else if (freeA > 0) {
    std::tie(chainB, chainA) = buildZZViaSwapAndShuttle(builder, loc, chainB, chainA, ionB, ionA, angle);
  } else {
    return op.emitOpError() << "cannot bring ions " << ionA << " and " << ionB
                            << " together: both traps are full, shuttling needs a free slot";
  }

  op.getAOut().replaceAllUsesWith(chainA);
  op.getBOut().replaceAllUsesWith(chainB);
  op.erase();

  return success();
}

namespace {

struct MagicShuttleInterTrapZZ final : impl::MagicShuttleInterTrapZZBase<MagicShuttleInterTrapZZ> {
  using MagicShuttleInterTrapZZBase::MagicShuttleInterTrapZZBase;

protected:
  void runOnOperation() override {
    SmallVector<InterTrapZZOp> ops;
    getOperation().walk([&](InterTrapZZOp op) { ops.push_back(op); });
    if (ops.empty()) {
      return;
    }

    const FailureOr<MagicDevice> device = MagicDevice::fromParentModuleChecked(getOperation());
    if (failed(device)) {
      return signalPassFailure();
    }

    for (InterTrapZZOp op : ops) {
      if (failed(lowerInterTrapZZ(op, *device))) {
        return signalPassFailure();
      }
    }
  }
};

} // namespace
} // namespace qcc::magic
