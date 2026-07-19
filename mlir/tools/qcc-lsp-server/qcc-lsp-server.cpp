//===- qcc-lsp-server.cpp - QCC custom MLIR LSP server -------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/Aux_/IR/Aux_.h"
#include "qcc/Dialect/Jasp/IR/Jasp.h"
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include "mlir/Dialect/QC/IR/QCDialect.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/InitAllDialects.h"
#include "mlir/Tools/mlir-lsp-server/MlirLspServerMain.h"

int main(int argc, char** argv) {
  mlir::DialectRegistry registry;

  // Register all builtin dialects and their extensions/interfaces.
  mlir::registerAllDialects(registry);

  // Register our custom project dialects.
  registry.insert<jasp::JaspDialect, mlir::qc::QCDialect, qcc::aux::AuxDialect, qcc::prelimhlep::PrelimHLEPDialect>();

  return mlir::succeeded(mlir::MlirLspServerMain(argc, argv, registry)) ? 0 : 1;
}
