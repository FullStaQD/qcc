// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "qcc/Target/TargetRegistry.h"

#include <mlir/Pass/PassManager.h>

namespace qcc {

/// Assembles the whole compilation pipeline for qcc.
void buildPipeline(mlir::PassManager& pm, const Target* target);

} // namespace qcc
