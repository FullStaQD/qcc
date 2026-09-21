// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// HiSEP-Q backend implementation. This is the ONLY place in the project allowed
// to depend on the HiSEP-Q LLVM fork (its headers and libraries); it is compiled
// only when QCC_ENABLE_HISEPQ is enabled.
//
// ===----------------------------------------------------------------------===//

#include "qcc/Target/HiSEPQ/HiSEPQTarget.h"

#include "qcc/Conversion/QCOToQVec/QCOToQVec.h"
#include "qcc/Conversion/ToHiSEPQ/HiSEPQMachine.h"
#include "qcc/Conversion/ToHiSEPQ/ToHiSEPQ.h"
#include "qcc/Dialect/QVec/Transforms/Passes.h"
#include "qcc/Target/QIR/QIRTarget.h"
#include "qcc/Target/TargetRegistry.h"

#include "mlir/Conversion/Passes.h"
#include "mlir/Conversion/QCToQCO/QCToQCO.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/Passes.h"

#include "llvm/IR/Function.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/CodeGen.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Target/TargetOptions.h"
#include "llvm/TargetParser/Triple.h"

#include <memory>
#include <optional>
#include <string>

namespace qcc {

/// The cap `qvec-merge` gets so that it never builds an operation wider than the QV instructions can address.
///
/// Zero (unbounded) for invalid options; `convert-qvec-to-hisepq-intrinsics` reports those.
static unsigned maxVectorizationFactor(const TargetOptions& targetOptions) {
  using hisepq::HiSEPQMachine;
  if (!HiSEPQMachine::isSupportedMinVLen(targetOptions.minVLen) ||
      !HiSEPQMachine::isSupportedQubitElementWidth(targetOptions.qubitElementWidth)) {
    return 0;
  }

  return HiSEPQMachine(targetOptions.minVLen, targetOptions.qubitElementWidth).maxQubits();
}

void addLoweringPassesHiSEPQViaQIR(mlir::PassManager& pm) {
  addLoweringPassesQIR(pm);
  pm.addPass(qcc::createConvertQIRToHiSEPQIntrinsics());
  pm.addPass(qcc::createEmitHiSEPQStart());
}

void addLoweringPassesHiSEPQViaQVec(mlir::PassManager& pm, const TargetOptions& targetOptions) {
  // qc -> qco -> qvec -> QV intrinsics
  pm.addPass(mlir::createQCToQCO());
  pm.addPass(qcc::createConvertQCOToQVec());

  QVecMergeOptions mergeOptions;
  mergeOptions.maxVF = maxVectorizationFactor(targetOptions);
  pm.addPass(qcc::createQVecMerge(mergeOptions));

  ConvertQVecToHiSEPQIntrinsicsOptions intrinsicsOptions;
  intrinsicsOptions.minVLen = targetOptions.minVLen;
  intrinsicsOptions.qubitElementWidth = targetOptions.qubitElementWidth;
  pm.addPass(qcc::createConvertQVecToHiSEPQIntrinsics(intrinsicsOptions));

  // Classical remainder to LLVM
  pm.addPass(mlir::createSCFToControlFlowPass());
  pm.addPass(mlir::createConvertVectorToLLVMPass());
  pm.addPass(mlir::createArithToLLVMConversionPass());
  pm.addPass(mlir::createConvertControlFlowToLLVMPass());
  pm.addPass(mlir::createConvertFuncToLLVMPass());

  pm.addPass(qcc::createEmitHiSEPQStart());

  // cleanup
  pm.addPass(mlir::createCanonicalizerPass());
  pm.addPass(mlir::createCSEPass());
}

bool emitNativeHiSEPQ(llvm::Module& module, llvm::raw_pwrite_stream& os, const NativeCodegenOptions& options,
                      const TargetOptions& targetOptions) {
  // HiSEP-Q QISA is encoded as the experimental "xqv" RISC-V vector extension,
  // provided by the HiSEP-Q LLVM fork.
  LLVMInitializeRISCVTargetInfo();
  LLVMInitializeRISCVTarget();
  LLVMInitializeRISCVTargetMC();
  LLVMInitializeRISCVAsmPrinter();
  LLVMInitializeRISCVAsmParser();

  // `zvl<N>b` is how RISC-V spells a guaranteed lower bound on VLEN, so this is the same machine parameter the
  // lowering above picked its vector types from; see `llvm::RISCVISAInfo::getMinVLen`. Handing it to the backend as
  // well keeps the two from reasoning about different machines. Note that the other extensions imply a lower bound of
  // their own, and the larger one wins.
  const std::string attrsStr = "+experimental-xqv,+zvl" + std::to_string(targetOptions.minVLen) + "b";
  llvm::Triple triple(llvm::Triple::normalize("riscv32-unknown-unknown"));

  std::string errorStr;
  const llvm::Target* theTarget = llvm::TargetRegistry::lookupTarget(/*MArch=*/"", triple, errorStr);
  if (theTarget == nullptr) {
    llvm::errs() << "could not find target '" << triple.str() << "': " << errorStr << "\n";
    return true;
  }

  llvm::TargetOptions llvmTargetOptions;
  // hisepq.ld puts `.text._start` at the boot address, which needs each function in its own
  // `.text.<name>` section, hence setting functionSections to true:
  llvmTargetOptions.FunctionSections = true;
  std::unique_ptr<llvm::TargetMachine> targetMachine(
      theTarget->createTargetMachine(triple, /*cpu=*/"", attrsStr, llvmTargetOptions, std::nullopt));

  // Nothing unwinds on HiSEP-Q. Without `nounwind` LLVM emits things like
  // `.cfi_startproc` (which is garbage for us).
  for (llvm::Function& func : module) {
    func.setDoesNotThrow(); // adds nounwind attribute
  }

  module.setDataLayout(targetMachine->createDataLayout());
  module.setTargetTriple(triple);

  const auto fileType = options.binary ? llvm::CodeGenFileType::ObjectFile : llvm::CodeGenFileType::AssemblyFile;

  llvm::legacy::PassManager codegenPM;
  if (targetMachine->addPassesToEmitFile(codegenPM, os, /*DwoOut=*/nullptr, fileType)) {
    llvm::errs() << "target machine cannot emit files of this type\n";
    return true;
  }
  codegenPM.run(module);
  return false;
}

} // namespace qcc
