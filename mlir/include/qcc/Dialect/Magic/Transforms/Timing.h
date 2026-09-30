// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "qcc/Dialect/Magic/Device/MagicDevice.h"
#include "qcc/Dialect/Magic/IR/Magic.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/Value.h"

#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>

namespace qcc::magic {

//===----------------------------------------------------------------------===//
// Timing segments
//===----------------------------------------------------------------------===//

/// The part of a program between two sync points: the program start, a `magic.shuttle`, the final measurement.
/// Between two sync points every trap must spend the same time.
struct TimingSegment {
  /// One trap that holds ions during the segment.
  struct Trap {
    /// The trap's chain value at the end of the segment.
    mlir::Value chain;
    /// The ticks of the trap's `magic.delay`s in the segment.
    Ticks ticks = 0;
  };

  /// The shuttle that ends the segment. Null for the last segment, which ends with the measurements.
  ShuttleOp end;
  /// The traps (by id) that hold ions, in the order their chains appear.
  llvm::MapVector<int64_t, Trap> traps;

  /// The largest sum of ticks of any trap in the segment.
  [[nodiscard]] Ticks getMaxTicks() const;
};

/// Splits the magic ops of `block` into segments, in program order. The ops of different traps are ordered by the
/// block, which for two traps agrees with the data flow: every shuttle involves both.
llvm::SmallVector<TimingSegment> getTimingSegments(mlir::Block& block);

} // namespace qcc::magic
