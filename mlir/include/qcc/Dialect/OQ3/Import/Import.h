// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"

#include "llvm/Support/SourceMgr.h"

#include <string>
#include <vector>

namespace qcc::oq3 {

struct ImportOptions {
  /// Directories to search for include files, after the directory of the including file.
  std::vector<std::string> includeDirs;
  /// Record an include file that cannot be found as an unresolved `oq3.include` instead of failing. Names that the
  /// file may define then become values of unknown type.
  bool allowUnresolvedIncludes = false;
};

/// Imports the OpenQASM 3 program in the main buffer of `sourceMgr` into a module of the `oq3` dialect. Included
/// files are added to `sourceMgr`, so that diagnostics can show their text.
///
/// Emits diagnostics through the context and returns null if the program is invalid or uses a construct that is not
/// supported yet. The result is verified.
mlir::OwningOpRef<mlir::ModuleOp> importOpenQASM(llvm::SourceMgr& sourceMgr, mlir::MLIRContext* context,
                                                 const ImportOptions& options = {});

/// Registers the translation `--import-openqasm` and its options (`-I`, `--oq3-allow-unresolved-includes`).
void registerImportOpenQASMTranslation();

} // namespace qcc::oq3
