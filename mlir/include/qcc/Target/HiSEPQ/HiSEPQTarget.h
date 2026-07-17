// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// Public entry point for the HiSEP-Q target.
//
// ===----------------------------------------------------------------------===//

#pragma once

#include <mlir/Pass/PassManager.h>

namespace qcc {

/// `Target::addLoweringPasses` for the HiSEP-Q target.
void addLoweringPassesHiSEPQ(mlir::PassManager& pm);

} // namespace qcc
