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
#include "mlir/IR/Value.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SmallVector.h"

#include <algorithm>
#include <cstdint>

using namespace mlir;

namespace qcc::magic {

Ticks TimingSegment::getMaxTicks() const {
  Ticks max = 0;
  for (const auto& [trap, entry] : traps) {
    max = std::max(max, entry.ticks);
  }
  return max;
}

SmallVector<TimingSegment> getTimingSegments(Block& block) {
  SmallVector<TimingSegment> segments;
  // Per trap the latest chain value and the ticks since the last sync point.
  llvm::MapVector<int64_t, TimingSegment::Trap> current;

  auto closeSegment = [&](ShuttleOp end) {
    TimingSegment& segment = segments.emplace_back();
    segment.end = end;
    for (auto& [trap, entry] : current) {
      if (cast<IonChainType>(entry.chain.getType()).getNumIons() > 0) {
        segment.traps.insert({trap, entry});
      }
      entry.ticks = 0;
    }
  };

  for (Operation& op : block) {
    if (auto shuttle = dyn_cast<ShuttleOp>(op)) {
      closeSegment(shuttle);
    }
    if (auto delay = dyn_cast<DelayOp>(op)) {
      current[delay.getChainIn().getType().getTrap()].ticks += static_cast<Ticks>(delay.getTicks());
    }
    for (Value result : op.getResults()) {
      if (auto type = dyn_cast<IonChainType>(result.getType())) {
        current[type.getTrap()].chain = result;
      }
    }
  }
  closeSegment(nullptr);
  return segments;
}

} // namespace qcc::magic
