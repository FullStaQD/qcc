// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/AffineRaise/AffineRaise.h"
#include "qcc/Conversion/Aux_/AuxOutputRecording.h"
#include "qcc/Conversion/JaspToQC/JaspToQC.h"
#include "qcc/Conversion/QCOToQVec/QCOToQVec.h"
#include "qcc/Conversion/ToHiSEPQ/ToHiSEPQ.h"
#include "qcc/Conversion/ToQIR/ToQIR.h"
#include "qcc/Dialect/Aux_/IR/Aux_.h"
#include "qcc/Dialect/Jasp/IR/Jasp.h"
#include "qcc/Dialect/QVec/IR/QVec.h"
#include "qcc/Dialect/QVec/Transforms/Passes.h"

#include "mlir/Conversion/ArithToLLVM/ArithToLLVM.h"
#include "mlir/Conversion/FuncToLLVM/ConvertFuncToLLVM.h"
#include "mlir/Conversion/Passes.h"
#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/Affine/Transforms/Passes.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Arith/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Bufferization/Transforms/FuncBufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/Transforms/Passes.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlow.h"
#include "mlir/Dialect/DLTI/DLTI.h"
#include "mlir/Dialect/Func/Extensions/InlinerExtension.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Linalg/Passes.h"
#include "mlir/Dialect/Linalg/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/MemRef/Transforms/AllocationOpInterfaceImpl.h"
#include "mlir/Dialect/MemRef/Transforms/Passes.h"
#include "mlir/Dialect/QC/IR/QCDialect.h"
#include "mlir/Dialect/QCO/IR/QCODialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/Tensor/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "mlir/Transforms/Passes.h"

int main(int argc, char** argv) {

  // Dialect registration
  mlir::DialectRegistry registry;

  registry.insert<
      // clang-format off
    mlir::affine::AffineDialect,
    mlir::func::FuncDialect,
    mlir::arith::ArithDialect,
    mlir::tensor::TensorDialect,
    mlir::bufferization::BufferizationDialect,
    mlir::linalg::LinalgDialect,
    mlir::cf::ControlFlowDialect,
    mlir::scf::SCFDialect,
    mlir::memref::MemRefDialect,
    mlir::LLVM::LLVMDialect,
    mlir::DLTIDialect,
    mlir::vector::VectorDialect,
    jasp::JaspDialect,
    mlir::qc::QCDialect,
    mlir::qco::QCODialect,
    qcc::aux::AuxDialect,
    qcc::qvec::QVecDialect
      // clang-format on
      >();

  // Builtin passes:
  mlir::registerCanonicalizerPass();
  mlir::registerCSEPass();
  mlir::registerArithToLLVMConversionPass();
  mlir::registerConvertControlFlowToLLVMPass();
  mlir::registerConvertVectorToLLVMPass();
  mlir::registerConvertLinalgToLoopsPass();
  mlir::bufferization::registerEmptyTensorToAllocTensorPass();
  mlir::bufferization::registerOneShotBufferizePass();
  mlir::bufferization::registerBufferLoopHoistingPass();
  mlir::registerMem2RegPass();
  mlir::registerSCCPPass();
  mlir::bufferization::registerPromoteBuffersToStackPass();
  mlir::registerInlinerPass();
  mlir::affine::registerAffineLoopUnroll();

  // Our passes
  qcc::registerAddEntrypointToMain();
  qcc::registerTmpRaiseSCFToAffinePass();
  qcc::registerWhileToFor();
  qcc::registerJaspToQC();
  qcc::registerConvertQCToQIR();
  qcc::registerPrepToQIR();
  qcc::registerFinalizeToQIR();
  qcc::registerAuxOutputRecording();
  qcc::registerJaspCheckStaticQubitAllocation();
  qcc::registerConvertMemrefToStaticQubits();
  mlir::registerConvertFuncToLLVMPass();
  qcc::registerConvertQIRToHiSEPQIntrinsics();
  qcc::registerEmitHiSEPQStart();
  qcc::registerConvertQCOToQVec();
  qcc::registerConvertQVecToHiSEPQIntrinsics();
  qcc::registerQVecMerge();

  // Extension registration
  mlir::arith::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::linalg::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::scf::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::tensor::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::bufferization::func_ext::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::memref::registerAllocationOpInterfaceExternalModels(registry);
  mlir::func::registerInlinerExtension(registry);
  qcc::qvec::registerQubitVectorElementTypeInterfaceExternalModel(registry);

  return mlir::asMainReturnCode(mlir::MlirOptMain(argc, argv, "qcc optimizer", registry));
}
