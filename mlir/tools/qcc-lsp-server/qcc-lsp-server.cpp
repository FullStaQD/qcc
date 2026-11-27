//===- qcc-lsp-server.cpp - QCC custom MLIR LSP server -------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "qcc/RegisterAllDialects.h"

#include "mlir/IR/DialectRegistry.h"
#include "mlir/InitAllDialects.h"
#include "mlir/Tools/mlir-lsp-server/MlirLspServerMain.h"

namespace qcc::test {
void registerTestDialect(mlir::DialectRegistry& registry);
} // namespace qcc::test

int main(int argc, char** argv) {
  mlir::DialectRegistry registry;

  // Register all builtin dialects and their extensions/interfaces.
  mlir::registerAllDialects(registry);

  // Register our dialects.
  qcc::registerAllDialects(registry);
  qcc::test::registerTestDialect(registry);

  return mlir::succeeded(mlir::MlirLspServerMain(argc, argv, registry)) ? 0 : 1;
}
