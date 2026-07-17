// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Target/QIR/QIRTarget.h"

#include "qcc/Conversion/Aux_/AuxOutputRecording.h"
#include "qcc/Conversion/ToQIR/ToQIR.h"

#include "mlir/Conversion/ArithToLLVM/ArithToLLVM.h"
#include "mlir/Conversion/ControlFlowToLLVM/ControlFlowToLLVM.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/Passes.h"

namespace qcc {

void addLoweringPassesQIR(mlir::PassManager& pm) {
  pm.addPass(qcc::createAuxOutputRecording());
  pm.addPass(qcc::createPrepToQIR());
  mlir::OpPassManager& fpm = pm.nest<mlir::func::FuncOp>();
  fpm.addPass(mlir::createArithToLLVMConversionPass());
  fpm.addPass(qcc::createConvertQCToQIR());
  pm.addPass(mlir::createConvertControlFlowToLLVMPass());
  pm.addPass(qcc::createFinalizeToQIR());

  // cleanup
  pm.addPass(mlir::createCanonicalizerPass());
  pm.addPass(mlir::createCSEPass());
  pm.addPass(mlir::createRemoveDeadValuesPass());
}

} // namespace qcc
