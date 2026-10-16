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

/// Prints the OpenQASM program `op` to `os`. The program is a module with the `oq3.version` attribute whose entry
/// function holds the statements, as the importer produces it.
///
/// Statements that an included file produced (`oq3.from_include`) are not printed; their `include` line is. Implicit
/// casts are not printed, and every expression is printed with the fewest parentheses that keep its structure.
llvm::LogicalResult exportOpenQASM(mlir::Operation* op, llvm::raw_ostream& os);

/// Registers the translation `--export-openqasm`.
void registerExportOpenQASMTranslation();

} // namespace qcc::oq3
