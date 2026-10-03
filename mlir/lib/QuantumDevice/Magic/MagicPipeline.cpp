// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/QuantumDevice/Magic/MagicPipeline.h"

#include "qcc/Conversion/Aux_/AuxOutputRecording.h"
#include "qcc/Conversion/Aux_/AuxUnpackRecordInt.h"
#include "qcc/Conversion/QCOToQVec/QCOToQVec.h"
#include "qcc/Conversion/QVecToMagic/QVecToMagic.h"
#include "qcc/Dialect/Magic/Transforms/Passes.h"
#include "qcc/Dialect/QVec/Transforms/Passes.h"

#include "mlir/Conversion/QCToQCO/QCToQCO.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/Passes.h"

namespace qcc {

void addLoweringPassesMagic(mlir::PassManager& pm) {
  // The classical output: one record per measured bit.
  pm.addPass(qcc::createAuxOutputRecording());
  pm.addPass(qcc::createAuxUnpackRecordInt());

  // qc -> qvec
  pm.addPass(mlir::createQCToQCO());
  pm.addPass(qcc::createConvertQCOToQVec());

  // The gates of the architecture: ZZ couplings and single-qubit rotations in ZXZ form, in alternating layers.
  pm.addPass(qcc::createQVecToRZZ());
  pm.addPass(qcc::createQVecToUZXZ());
  pm.addPass(qcc::createQVecFuseZXZ());
  pm.addPass(qcc::createQVecLayer());

  // qvec -> magic, then down to the native ops.
  mlir::OpPassManager& lowering = pm.nest<mlir::func::FuncOp>();
  lowering.addPass(qcc::createConvertQVecToMagic());
  lowering.addPass(qcc::magic::createMagicShuttleInterTrapZZ());
  lowering.addPass(qcc::magic::createMagicCompileSwap());
  lowering.addPass(qcc::magic::createMagicCompileActiveZZTrivially());
  lowering.addPass(qcc::magic::createMagicFinalizeZXZ());

  // Cleanup. It also removes what does not contribute to a recorded result.
  pm.addPass(mlir::createCanonicalizerPass());

  // Complete the program for the device and check it.
  mlir::OpPassManager& completion = pm.nest<mlir::func::FuncOp>();
  completion.addPass(qcc::magic::createMagicMeasureAndRecordGarbage());
  completion.addPass(qcc::magic::createMagicCompactIonIds());
  completion.addPass(qcc::magic::createMagicPadTiming());
  completion.addPass(qcc::magic::createMagicVerify());
}

} // namespace qcc
