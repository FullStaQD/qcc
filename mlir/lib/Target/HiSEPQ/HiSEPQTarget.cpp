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

#include "mlir/Conversion/Passes.h" // IWYU pragma: keep
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

#include <algorithm>
#include <array>
#include <memory>
#include <optional>
#include <string>

namespace qcc {

// NOTE: LLVM uses tablegen for this, we are a bit more low-tech here and use macros.
#define HISEPQ_ZVL(N) {.name = "zvl" #N "b", .description = "VLEN of at least " #N " bits"}
#define HISEPQ_XQVEL(N)                                                                                                \
  {.name = "xqvel" #N "b", .description = "Qubit element length of at least " #N " bits, aka QELEN"}
static constexpr auto hisepqFeatureTable = std::to_array<Feature>({
    HISEPQ_ZVL(64),
    HISEPQ_ZVL(128),
    HISEPQ_ZVL(256),
    HISEPQ_ZVL(512),
    HISEPQ_ZVL(1024),
    HISEPQ_ZVL(2048),
    HISEPQ_ZVL(4096),
    HISEPQ_ZVL(8192),
    HISEPQ_ZVL(16384),
    HISEPQ_ZVL(32768),
    HISEPQ_ZVL(65536),
    HISEPQ_XQVEL(8),
    HISEPQ_XQVEL(16),
});
#undef HISEPQ_ZVL
#undef HISEPQ_XQVEL
const llvm::ArrayRef<Feature> hisepqFeatures = hisepqFeatureTable;

// TODO: Add CPUs for concrete HiSEP-Q builds, e.g. one with a VLEN of 128 and 16 qubit control lines.
static constexpr auto genericFeatures = std::to_array<llvm::StringRef>({"zvl64b", "xqvel8b"});
static constexpr auto hisepqCpuTable = std::to_array<Cpu>({
    {.name = "generic",
     .description = "VLEN of at least 64 and the 256 qubit control lines that 8-bit indices address",
     .features = genericFeatures,
     .numQubitControlLines = 256},
});
const llvm::ArrayRef<Cpu> hisepqCpus = hisepqCpuTable;

/// Parses `N` out of a feature name of the form `<prefix><N><suffix>`.
static std::optional<unsigned> boundOf(llvm::StringRef name, llvm::StringRef prefix, llvm::StringRef suffix) {
  unsigned value = 0;
  if (!name.consume_front(prefix) || !name.consume_back(suffix) || name.getAsInteger(10, value)) {
    return std::nullopt;
  }
  return value;
}

/// Applies `features` in order and returns the largest `<prefix><N><suffix>` enabled. As in LLVM for `zvl<N>b`, a
/// feature implies every one with a smaller N, so disabling it disables every one with a larger N too.
static std::optional<unsigned> largestEnabledFor(llvm::ArrayRef<FeatureFlag> features, llvm::StringRef prefix,
                                                 llvm::StringRef suffix) {
  std::optional<unsigned> bound;
  for (const FeatureFlag& feature : features) {
    const std::optional<unsigned> value = boundOf(feature.name, prefix, suffix);
    if (!value) {
      continue;
    }
    if (feature.enable) {
      bound = std::max(bound.value_or(0), *value);
      continue;
    }
    if (!bound || *bound < *value) {
      continue;
    }
    // Disabling `value` disables every larger bound too, leaving the largest known one below it.
    bound.reset();
    for (const Feature& known : hisepqFeatureTable) {
      const std::optional<unsigned> knownValue = boundOf(known.name, prefix, suffix);
      if (knownValue && *knownValue < *value) {
        bound = std::max(bound.value_or(0), *knownValue);
      }
    }
  }
  return bound;
}

/// The machine `features` and `numQubitControlLines` describe; reports an error and returns nullopt if they describe
/// none.
static std::optional<hisepq::HiSEPQMachine> machineFor(llvm::ArrayRef<FeatureFlag> features,
                                                       unsigned numQubitControlLines) {
  const std::optional<unsigned> minVLen = largestEnabledFor(features, "zvl", "b");
  if (!minVLen) {
    llvm::errs() << "error: -mcpu and -mattr leave no 'zvl<N>b' feature enabled\n";
    return std::nullopt;
  }

  // QELEN, the widest qubit index the machine reads.
  const std::optional<unsigned> maxQubitElementWidth = largestEnabledFor(features, "xqvel", "b");
  if (!maxQubitElementWidth) {
    llvm::errs() << "error: -mcpu and -mattr leave no 'xqvel<N>b' feature enabled\n";
    return std::nullopt;
  }

  const unsigned maxLines = hisepq::HiSEPQMachine::maxNumQubitControlLinesFor(*maxQubitElementWidth);
  if (numQubitControlLines < 1 || numQubitControlLines > maxLines) {
    llvm::errs() << "error: -mqcl expects 1 to " << maxLines << " qubit control lines for a QELEN of "
                 << *maxQubitElementWidth << ", got " << numQubitControlLines;
    if (*maxQubitElementWidth < 16 && numQubitControlLines > maxLines) {
      llvm::errs() << " (16-bit qubit indices need -mattr=+xqvel16b)";
    }
    llvm::errs() << "\n";
    return std::nullopt;
  }
  return hisepq::HiSEPQMachine(*minVLen, numQubitControlLines);
}

void addLoweringPassesHiSEPQViaQIR(mlir::PassManager& pm) {
  addLoweringPassesQIR(pm);
  pm.addPass(qcc::createConvertQIRToHiSEPQIntrinsics());
  // Promotes the stack slots that hold measurement results to SSA values.
  pm.addPass(mlir::createMem2Reg());
  pm.addPass(qcc::createEmitHiSEPQStart());
}

mlir::LogicalResult addLoweringPassesHiSEPQ(mlir::PassManager& pm, llvm::ArrayRef<FeatureFlag> features,
                                            unsigned numQubitControlLines) {
  const std::optional<hisepq::HiSEPQMachine> machine = machineFor(features, numQubitControlLines);
  if (!machine) {
    return mlir::failure();
  }

  // qc -> qco -> qvec -> QV intrinsics
  pm.addPass(mlir::createQCToQCO());
  pm.addPass(qcc::createConvertQCOToQVec());

  QVecMergeOptions mergeOptions;
  mergeOptions.maxVF = machine->maxQubits();
  pm.addPass(qcc::createQVecMerge(mergeOptions));

  ConvertQVecToHiSEPQIntrinsicsOptions intrinsicsOptions;
  intrinsicsOptions.minVLen = machine->getMinVLen();
  intrinsicsOptions.numQubitControlLines = machine->getNumQubitControlLines();
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
  return mlir::success();
}

bool emitNativeHiSEPQ(llvm::Module& module, llvm::raw_pwrite_stream& os, const NativeCodegenOptions& options,
                      llvm::ArrayRef<FeatureFlag> features, unsigned numQubitControlLines) {
  // HiSEP-Q QISA is encoded as the experimental "xqv" RISC-V vector extension,
  // provided by the HiSEP-Q LLVM fork.
  LLVMInitializeRISCVTargetInfo();
  LLVMInitializeRISCVTarget();
  LLVMInitializeRISCVTargetMC();
  LLVMInitializeRISCVAsmPrinter();
  LLVMInitializeRISCVAsmParser();

  const std::optional<hisepq::HiSEPQMachine> machine = machineFor(features, numQubitControlLines);
  if (!machine) {
    return true;
  }
  // `enable-vsetvli-sched-heuristic` lets the machine scheduler break ties in favour of the current vector
  // configuration. Alone it changes nothing, but it keeps `generic-ooo` (see below) from adding `vsetvli`s when qubit
  // indices and their gate differ in LMUL, as at the default `zvl64b`.
  const std::string attrsStr =
      "+experimental-xqv,+zvl" + std::to_string(machine->getMinVLen()) + "b,+enable-vsetvli-sched-heuristic";
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
  //
  // The default tuning (`generic-rv32`) schedules for an in-order application core: to avoid a pipeline stall it moves
  // a vector's definition away from its use, e.g. the qubit indices of a measurement above gates of another vector
  // configuration, which costs extra `vsetvli`s. `generic-ooo` models no such stall and keeps them together.
  // TODO: Tune for a dedicated HiSEP-Q CPU model once the LLVM fork defines one.
  for (llvm::Function& func : module) {
    func.setDoesNotThrow(); // adds nounwind attribute
    func.addFnAttr("tune-cpu", "generic-ooo");
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
