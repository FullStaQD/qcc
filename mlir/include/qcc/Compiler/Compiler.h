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

/// Assembles the pipeline that makes elaborated Mojo IR a PrelimHLEP program.
///
/// This is the residue translation and nothing else, so that running it and
/// the verification the pass manager does after it is exactly what
/// `--verify-only` promises: every rule qcc owns has been checked, and no
/// lowering decision has been taken yet. It is also the point at which the
/// module is a function-level program whose entry points can be written to
/// the sidecar, before the inliner and the QCO lowering rewrite the
/// signatures.
void buildMojoResiduePipeline(mlir::PassManager& pm);

/// Assembles the pipeline that lowers a PrelimHLEP program to QCO.
///
/// Runs on the output of `buildMojoResiduePipeline`: the inliner that
/// flattens the eDSL's one call per gate, and the lowering to QCO. When
/// `target` is null the pipeline stops at QCO; otherwise
/// `buildQCOLoweringPipeline` continues it to that target.
void buildMojoLoweringPipeline(mlir::PassManager& pm, const Target* target = nullptr);

/// Assembles the pipeline that lowers a QCO program to `target`.
///
/// This is the entry a frontend that ends at QCO takes into the target
/// backends, which model qubits the way QIR does: a fixed register file,
/// addressed by index, acted on by one- and two-qubit gates. So the QCO
/// program is first made to fit that model -- multi-controlled gates are
/// decomposed, dynamic allocations are given static indices -- and only then
/// translated into QC, which is where `Target::addLoweringPasses` picks it up.
///
/// The entry point is whichever function carries `qcc.entry_point`; unlike
/// the JASP path this pipeline does not impose a naming convention, so the
/// frontend sets the attribute.
void buildQCOLoweringPipeline(mlir::PassManager& pm, const Target* target);

} // namespace qcc
