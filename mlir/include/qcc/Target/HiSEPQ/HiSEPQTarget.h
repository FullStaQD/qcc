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

#include "qcc/Target/TargetRegistry.h"

#include "mlir/Pass/PassManager.h"

namespace qcc {

/// `Target::addLoweringPasses` for the HiSEP-Q target.
void addLoweringPassesHiSEPQ(mlir::PassManager& pm);

/// `Target::emitNative` for the HiSEP-Q target: lowers the QV-intrinsic LLVM
/// module to RISC-V assembly or an object file. Returns true on failure.
bool emitNativeHiSEPQ(llvm::Module& module, llvm::raw_pwrite_stream& os, const NativeCodegenOptions& options);

} // namespace qcc
