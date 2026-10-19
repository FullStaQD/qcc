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

#include "llvm/ADT/STLFunctionalExtras.h"

namespace qcc::magic {

//===----------------------------------------------------------------------===//
// Trap clocks
//===----------------------------------------------------------------------===//

/// Walks `block` in order and calls `callback` for every shuttle whose two traps are not in sync, with the clocks of
/// its source and its destination trap.
///
/// The walk goes on as if the imbalance had been padded away: both traps continue at the later of the two clocks.
/// So every imbalance is seen once and not again at the next shuttle, and the callback either pads the trap that is
/// behind (in front of the shuttle) or reports it.
void forEachUnbalancedShuttle(mlir::Block& block,
                              llvm::function_ref<void(ShuttleOp shuttle, Ticks fromTicks, Ticks toTicks)> callback);

} // namespace qcc::magic
