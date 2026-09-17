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

/// Assembles the pipeline that turns elaborated Mojo IR into QCO.
///
/// This is the front half of the PrelimHLEP path: the residue translation
/// that makes a Mojo module a PrelimHLEP program, the inliner that flattens
/// the eDSL's calls, and the lowering to QCO. It stops there, because the
/// lowering from QCO to a target does not exist yet; see `mojo/README.md`.
void buildMojoFrontendPipeline(mlir::PassManager& pm);

} // namespace qcc
