// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

namespace mlir {
class DialectRegistry;
} // namespace mlir

namespace qcc {

/// Adds the dialects qcc works with to `registry`: ours and the upstream ones that Qrisp emits or our pipeline
/// produces, together with their interface models and extensions.
void registerAllDialects(mlir::DialectRegistry& registry);

} // namespace qcc
