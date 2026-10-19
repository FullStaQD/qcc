// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/Transforms/Timing.h"

#include "qcc/Dialect/Magic/Device/MagicDevice.h"
#include "qcc/Dialect/Magic/IR/Magic.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/Operation.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLFunctionalExtras.h"

#include <algorithm>
#include <cstdint>

using namespace mlir;

namespace qcc::magic {

void forEachUnbalancedShuttle(Block& block, function_ref<void(ShuttleOp, Ticks, Ticks)> callback) {
  // Per trap (id) the ticks spent so far.
  llvm::DenseMap<int64_t, Ticks> clocks;
  for (Operation& op : block) {
    if (auto delay = dyn_cast<DelayOp>(op)) {
      clocks[delay.getChainIn().getType().getTrap()] += static_cast<Ticks>(delay.getTicks());
      continue;
    }

    auto shuttle = dyn_cast<ShuttleOp>(op);
    if (!shuttle) {
      continue;
    }

    const int64_t from = shuttle.getFromIn().getType().getTrap();
    const int64_t to = shuttle.getToIn().getType().getTrap();
    const Ticks fromTicks = clocks.lookup(from);
    const Ticks toTicks = clocks.lookup(to);

    if (fromTicks == toTicks) {
      continue;
    }

    callback(shuttle, fromTicks, toTicks);
    // As if the trap that is behind had been padded.
    clocks[from] = clocks[to] = std::max(fromTicks, toTicks);
  }
}

} // namespace qcc::magic
