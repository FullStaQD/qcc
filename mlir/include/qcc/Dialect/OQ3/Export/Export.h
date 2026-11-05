// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/IR/Operation.h"

#include "llvm/Support/LogicalResult.h"
#include "llvm/Support/raw_ostream.h"

namespace qcc::oq3 {

/// Exports the module `op` to an OpenQASM 3.0 program and writes it to `os`.
/// `op` must be a valid OpenQASM 3.0 module operation. `oq3.version` attribute and legal according to the OQ3 dialect.
llvm::LogicalResult exportOpenQASM(mlir::Operation* op, llvm::raw_ostream& os);

/// Registers the translation `--export-openqasm`.
void registerExportOpenQASMTranslation();

} // namespace qcc::oq3
