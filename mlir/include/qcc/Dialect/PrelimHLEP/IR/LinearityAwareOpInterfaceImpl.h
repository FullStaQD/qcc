// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include <mlir/IR/DialectRegistry.h>

namespace qcc::prelimhlep {

/// Attaches `LinearityAwareOpInterface` to the ops of other dialects (`scf`,
/// `func`) that may handle values subject to linearity inside a
/// `prelimhlep.halo` function.
void registerLinearityAwareOpInterfaceExternalModels(mlir::DialectRegistry& registry);

} // namespace qcc::prelimhlep
