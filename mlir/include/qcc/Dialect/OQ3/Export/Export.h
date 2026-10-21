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

/// Writes `op`, an `oq3` module like the importer builds it, to `os` as OpenQASM source.
///
/// The output is canonical rather than a copy of the original source: an included file appears only as its `include`
/// line, implicit casts are left out, and expressions get only the parentheses they need. Fails with a diagnostic on
/// IR that has no OpenQASM form.
llvm::LogicalResult exportOpenQASM(mlir::Operation* op, llvm::raw_ostream& os);

/// Registers the translation `--export-openqasm`.
void registerExportOpenQASMTranslation();

} // namespace qcc::oq3
