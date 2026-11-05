// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/OQ3/Export/Export.h"
#include "qcc/Dialect/OQ3/Import/Import.h"

#include "mlir/Tools/mlir-translate/MlirTranslateMain.h"

int main(int argc, char** argv) {
  qcc::oq3::registerImportOpenQASMTranslation();
  qcc::oq3::registerExportOpenQASMTranslation();

  return mlir::failed(mlir::mlirTranslateMain(argc, argv, "qcc translation tool")) ? 1 : 0;
}
