// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "qcc/QuantumDevice/QuantumDeviceRegistry.h"
#include "qcc/Target/TargetRegistry.h"

#include <llvm/ADT/StringRef.h>
#include <mlir/Pass/PassManager.h>

namespace qcc {

/// Assembles the whole compilation pipeline for qcc: the frontend lowering, then the lowering for the quantum device
/// and finally the lowering for the target.
///
/// A non-empty `deviceDescription` is the path of a device file. Its device description is attached to the module
/// (`qcc.device`) before anything else runs.
///
/// Fails if `features` describe no machine of `target`.
mlir::LogicalResult buildPipeline(mlir::PassManager& pm, const Target* target, llvm::ArrayRef<FeatureFlag> features,
                                  const QuantumDeviceKind* quantumDevice, llvm::StringRef deviceDescription);

} // namespace qcc
