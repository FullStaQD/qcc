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

static constexpr Feature hisepqFeatureTable[] = {
    {"zvl64b", "Minimum vector length 64 bits (the default)"},
    {"zvl128b", "Minimum vector length 128 bits"},
    {"zvl256b", "Minimum vector length 256 bits"},
    {"zvl512b", "Minimum vector length 512 bits"},
    {"zvl1024b", "Minimum vector length 1024 bits"},
    {"zvl2048b", "Minimum vector length 2048 bits"},
    {"zvl4096b", "Minimum vector length 4096 bits"},
    {"zvl8192b", "Minimum vector length 8192 bits"},
    {"zvl16384b", "Minimum vector length 16384 bits"},
    {"zvl32768b", "Minimum vector length 32768 bits"},
    {"zvl65536b", "Minimum vector length 65536 bits"},
    {"qew8", "8-bit qubit indices (the default)"},
    {"qew16", "16-bit qubit indices"},
};
const llvm::ArrayRef<Feature> hisepqFeatures = hisepqFeatureTable;

/// The machine `features` describe; the last of a kind wins.
static hisepq::HiSEPQMachine machineFor(llvm::ArrayRef<llvm::StringRef> features) {
  unsigned minVLen = 64;
  unsigned qubitElementWidth = 8;
  for (llvm::StringRef feature : features) {
    if (feature.consume_front("zvl")) {
      feature.consume_back("b");
      feature.getAsInteger(10, minVLen);
    } else if (feature.consume_front("qew")) {
      feature.getAsInteger(10, qubitElementWidth);
    }
  }
  return {minVLen, qubitElementWidth};
}

void addLoweringPassesHiSEPQViaQIR(mlir::PassManager& pm) {
  addLoweringPassesQIR(pm);
  pm.addPass(qcc::createConvertQIRToHiSEPQIntrinsics());
  pm.addPass(qcc::createEmitHiSEPQStart());
}

void addLoweringPassesHiSEPQ(mlir::PassManager& pm, llvm::ArrayRef<llvm::StringRef> features) {
  const hisepq::HiSEPQMachine machine = machineFor(features);

  // qc -> qco -> qvec -> QV intrinsics
  pm.addPass(mlir::createQCToQCO());
  pm.addPass(qcc::createConvertQCOToQVec());

  QVecMergeOptions mergeOptions;
  mergeOptions.maxVF = machine.maxQubits();
  pm.addPass(qcc::createQVecMerge(mergeOptions));

  ConvertQVecToHiSEPQIntrinsicsOptions intrinsicsOptions;
  intrinsicsOptions.minVLen = machine.getMinVLen();
  intrinsicsOptions.qubitElementWidth = machine.getQubitElementWidth();
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
                      llvm::ArrayRef<llvm::StringRef> features) {
  // HiSEP-Q QISA is encoded as the experimental "xqv" RISC-V vector extension,
  // provided by the HiSEP-Q LLVM fork.
  LLVMInitializeRISCVTargetInfo();
  LLVMInitializeRISCVTarget();
  LLVMInitializeRISCVTargetMC();
  LLVMInitializeRISCVAsmPrinter();
  LLVMInitializeRISCVAsmParser();

  // QEW is not forwarded; the backend does not know it.
  const std::string attrsStr = "+experimental-xqv,+zvl" + std::to_string(machineFor(features).getMinVLen()) + "b";
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
