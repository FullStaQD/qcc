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

/// Every trap has its own clock: the ticks of the `magic.delay`s on its chain since the program start. A
/// `magic.shuttle` is a sync point for its two traps, which must have spent the same time when it happens. Nothing
/// else relates the clocks of two traps.
///
/// Walks `block` in order and calls `callback` for every shuttle with the clocks of its source and its destination
/// trap. Both traps continue at the later of the two clocks, so the callback may pad the trap that is behind (in
/// front of the shuttle) or report it.
void forEachShuttleSync(mlir::Block& block,
                        llvm::function_ref<void(ShuttleOp shuttle, Ticks fromTicks, Ticks toTicks)> callback);

} // namespace qcc::magic
