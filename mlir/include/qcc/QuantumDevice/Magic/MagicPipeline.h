// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// Public entry point for the MAGIC quantum device.
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/Pass/PassManager.h"

namespace qcc {

/// `QuantumDevice::addLoweringPasses` for MAGIC devices: from QC to verified magic IR with native ops only, ready for
/// `magic::exportProgram`. Expects the module to carry a `#magic.device` as `qcc.device`.
void addLoweringPassesMagic(mlir::PassManager& pm);

} // namespace qcc
