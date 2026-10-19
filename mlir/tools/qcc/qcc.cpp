// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "qcc/Compiler/Compiler.h"
#include "qcc/Dialect/Aux_/IR/Aux_.h"
#include "qcc/Dialect/Jasp/IR/Jasp.h"
#include "qcc/Dialect/Magic/IR/Magic.h"
#include "qcc/Dialect/QCirc/IR/QCirc.h"
#include "qcc/Dialect/QVec/IR/QVec.h"
#include "qcc/QuantumDevice/QuantumDeviceRegistry.h"
#include "qcc/Target/TargetRegistry.h"

#include "mlir/Bytecode/BytecodeWriter.h"
#include "mlir/Conversion/VectorToSCF/VectorToSCF.h"
#include "mlir/Dialect/Arith/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/Transforms/FuncBufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/Transforms/Passes.h"
#include "mlir/Dialect/Func/Extensions/InlinerExtension.h"
#include "mlir/Dialect/Linalg/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/MemRef/Transforms/AllocationOpInterfaceImpl.h"
#include "mlir/Dialect/MemRef/Transforms/Passes.h"
#include "mlir/Dialect/QC/IR/QCDialect.h"
#include "mlir/Dialect/QCO/IR/QCODialect.h"
#include "mlir/Dialect/SCF/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Tensor/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/InitAllDialects.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/FileUtilities.h"
#include "mlir/Target/LLVMIR/Dialect/Builtin/BuiltinToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Dialect/LLVMIR/LLVMToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Export.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/SystemUtils.h"
#include "llvm/Support/ToolOutputFile.h"

#include <cstdint>
#include <string>
#include <utility>

namespace cl = llvm::cl;

static cl::OptionCategory qccCategory("QCC options");

namespace {
/// The stage to compile to and emit.
enum class Stage : uint8_t { Mlir, LlvmIr, Native, CustomMagic };
} // namespace

/// Prints the targets compiled into this build.
static void printTargets() {
  llvm::outs() << "Available targets for --target:\n";
  for (const qcc::Target& backend : qcc::getTargets()) {
    llvm::outs() << "  " << backend.name << " - " << backend.description << "\n";
    for (const qcc::Cpu& cpu : backend.cpus) {
      llvm::outs() << "    -mcpu=" << cpu.name << " - " << cpu.description;
      if (!cpu.features.empty()) {
        llvm::outs() << " (-mattr=+" << llvm::join(cpu.features, ",+") << ")";
      }
      if (cpu.numQubitControlLines != 0) {
        llvm::outs() << " (-mqcl=" << cpu.numQubitControlLines << ")";
      }
      llvm::outs() << (cpu.name == "generic" ? " [default]\n" : "\n");
    }
    for (const qcc::Feature& feature : backend.features) {
      llvm::outs() << "    -mattr=+" << feature.name << " - " << feature.description << "\n";
    }
  }
}

/// Prints the quantum devices compiled into this build.
static void printQuantumDevices() {
  llvm::outs() << "Available quantum devices for --quantum-device:\n";
  for (const qcc::QuantumDeviceKind& device : qcc::getQuantumDeviceKinds()) {
    llvm::outs() << "  " << device.name << " - " << device.description << "\n";
  }
}

int main(int argc, char** argv) {
  mlir::registerMLIRContextCLOptions();
  mlir::registerPassManagerCLOptions();
  mlir::registerDefaultTimingManagerCLOptions();

  const cl::opt<std::string> inputFilename(cl::Positional, cl::desc("Input-file"), cl::cat(qccCategory));
  const cl::opt<std::string> outputFilename("o", cl::desc("Output-file"), cl::value_desc("filename"), cl::init("-"),
                                            cl::cat(qccCategory));
  const cl::opt<std::string> targetOption(
      "target",
      cl::desc("Target backend to compile for (see --list-targets). Default: qir, or none with a quantum device"),
      cl::init("qir"), cl::value_desc("name"), cl::cat(qccCategory));
  const cl::opt<bool> listTargets("list-targets", cl::desc("List the available --target backends and exit"),
                                  cl::init(false), cl::cat(qccCategory));
  const cl::opt<std::string> quantumDeviceName(
      "quantum-device",
      cl::desc("Kind of quantum device to lower for (see --list-quantum-devices). Implies --target=none by default."),
      cl::init(qcc::noQuantumDeviceName.str()), cl::value_desc("name"), cl::cat(qccCategory));
  const cl::opt<bool> listQuantumDevices("list-quantum-devices",
                                         cl::desc("List the available --quantum-device kinds and exit"),
                                         cl::init(false), cl::cat(qccCategory));
  const cl::opt<std::string> deviceDescription(
      "device-description",
      cl::desc("Device file that describes the quantum device (requires --quantum-device). Not needed if the input "
               "module already carries a 'qcc.device' attribute"),
      cl::value_desc("filename"), cl::cat(qccCategory));
  const cl::opt<std::string> mcpu("mcpu", cl::desc("Target CPU (see --list-targets)"), cl::init("generic"),
                                  cl::value_desc("name"), cl::cat(qccCategory));
  const cl::opt<std::string> mattr("mattr", cl::desc("Target features, comma-separated (see --list-targets)"),
                                   cl::value_desc("+feature,-feature,..."), cl::cat(qccCategory));
  cl::opt<unsigned> mqcl("mqcl",
                         cl::desc("Number of qubit control lines the machine drives (default: the CPU's, see "
                                  "--list-targets)"),
                         cl::value_desc("N"), cl::cat(qccCategory));
  const cl::alias mqclAlias("mqubit-control-lines", cl::desc("Alias for -mqcl"), cl::aliasopt(mqcl), cl::NotHidden,
                            cl::cat(qccCategory));
  const cl::opt<Stage> compileTo(
      "compile-to", cl::desc("Stage to lower to and emit"), cl::init(Stage::LlvmIr),
      cl::values(clEnumValN(Stage::Mlir, "mlir", "MLIR after all lowering"),
                 clEnumValN(Stage::LlvmIr, "llvmir", "LLVM IR (QIR for the QIR target)"),
                 clEnumValN(Stage::Native, "native", "Native target code (QISA; requires a target with a backend)"),
                 clEnumValN(Stage::CustomMagic, "custom-magic",
                            "Temporary OpenQASM-like text format for MAGIC devices (requires --quantum-device=magic)")),
      cl::cat(qccCategory));
  const cl::opt<bool> binary("binary", cl::desc("Emit the binary encoding (obj/bytecode/bitcode) instead of text"),
                             cl::init(false), cl::cat(qccCategory));

  cl::ParseCommandLineOptions(argc, argv, "qcc - Quantum Compiler Collection\n");

  if (listTargets) {
    printTargets();
    return 0;
  }

  if (listQuantumDevices) {
    printQuantumDevices();
    return 0;
  }

  if (inputFilename.empty()) {
    llvm::errs() << "error: no input file specified\n";
    return 1;
  }

  const qcc::QuantumDeviceKind* quantumDevice = qcc::lookupQuantumDeviceKind(quantumDeviceName);
  if (quantumDevice == nullptr) {
    llvm::errs() << "error: unknown quantum device '" << quantumDeviceName << "' (see --list-quantum-devices)\n";
    return 1;
  }
  const bool hasQuantumDevice = quantumDevice->name != qcc::noQuantumDeviceName;

  // A quantum device is lowered for without a QISA so far, so it implies the target "none".
  const bool targetGiven = targetOption.getNumOccurrences() > 0;
  const std::string targetName = (hasQuantumDevice && !targetGiven) ? qcc::noTargetName.str() : targetOption.getValue();
  const qcc::Target* target = qcc::lookupTarget(targetName);
  if (target == nullptr) {
    llvm::errs() << "error: unknown target '" << targetName << "' (see --list-targets)\n";
    return 1;
  }

  if (hasQuantumDevice && target->name != qcc::noTargetName) {
    llvm::errs() << "error: --quantum-device=" << quantumDeviceName << " and --target=" << targetName
                 << " are not supported together (use --target=" << qcc::noTargetName << ")\n";
    return 1;
  }

  if (!hasQuantumDevice && deviceDescription.getNumOccurrences() > 0) {
    llvm::errs() << "error: --device-description requires a quantum device (see --quantum-device)\n";
    return 1;
  }

  if (compileTo == Stage::CustomMagic && quantumDevice->name != "magic") {
    llvm::errs() << "error: --compile-to=custom-magic requires --quantum-device=magic\n";
    return 1;
  }

  if (compileTo == Stage::CustomMagic && binary) {
    llvm::errs() << "error: --binary is not supported for --compile-to=custom-magic\n";
    return 1;
  }

  if (compileTo == Stage::Native && !target->emitNative) {
    llvm::errs() << "error: native output is not supported for --target=" << targetName << "\n";
    return 1;
  }

  if (compileTo == Stage::LlvmIr && !target->lowersToLLVM) {
    // LLVM IR is the default stage, so this is what a run without --compile-to ends in.
    llvm::errs() << "error: LLVM IR output (--compile-to=llvmir, the default) is not supported for --target="
                 << targetName << "; choose the stage explicitly: --compile-to=mlir";
    if (quantumDevice->name == "magic") {
      llvm::errs() << " or --compile-to=custom-magic";
    }
    llvm::errs() << "\n";
    return 1;
  }

  const qcc::Cpu* cpu = qcc::lookupCpu(*target, mcpu);
  if (cpu == nullptr) {
    llvm::errs() << "error: unknown CPU '" << mcpu << "' for --target=" << targetName << "\n";
    return 1;
  }

  const mlir::FailureOr<llvm::SmallVector<qcc::FeatureFlag>> features = qcc::parseFeatures(*target, *cpu, mattr);
  if (mlir::failed(features)) {
    return 1;
  }

  if (mqcl.getNumOccurrences() > 0 && cpu->numQubitControlLines == 0) {
    llvm::errs() << "error: -mqcl is not supported for --target=" << targetName << "\n";
    return 1;
  }
  const unsigned numQubitControlLines = mqcl.getNumOccurrences() > 0 ? mqcl : cpu->numQubitControlLines;

  mlir::DialectRegistry registry;

  // Register all builtin dialects and their extensions/interfaces:
  mlir::registerAllDialects(registry);

  // Our dialects:
  registry.insert<jasp::JaspDialect, mlir::qc::QCDialect, mlir::qco::QCODialect, qcc::aux::AuxDialect,
                  qcc::magic::MagicDialect, qcc::QccDialect, qcc::qcirc::QCircDialect, qcc::qvec::QVecDialect>();

  // Register the specific interface implementations for the pipeline
  // Note: OneShotBufferize requires these for the "Standard" dialects
  mlir::arith::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::linalg::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::scf::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::tensor::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::bufferization::func_ext::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::memref::registerAllocationOpInterfaceExternalModels(registry);
  mlir::func::registerInlinerExtension(registry);

  // For emitting LLVM IR:
  mlir::registerBuiltinDialectTranslation(registry);
  mlir::registerLLVMDialectTranslation(registry);

  mlir::MLIRContext context(registry);

  std::string errorMessage;
  auto inFile = mlir::openInputFile(inputFilename, &errorMessage);
  if (!inFile) {
    llvm::errs() << errorMessage << "\n";
    return 1;
  }

  llvm::SourceMgr sourceMgr;
  sourceMgr.AddNewSourceBuffer(std::move(inFile), llvm::SMLoc());

  // Enable nice diagnostic printing for parser and pass errors
  const mlir::SourceMgrDiagnosticHandler diagnosticHandler(sourceMgr, &context);

  mlir::OwningOpRef<mlir::ModuleOp> module = mlir::parseSourceFile<mlir::ModuleOp>(sourceMgr, &context);
  if (!module) {
    return 1;
  }

  mlir::PassManager pm(&context);
  if (mlir::failed(mlir::applyPassManagerCLOptions(pm))) {
    return 1;
  }

  if (mlir::failed(qcc::buildPipeline(pm, target, *features, numQubitControlLines, quantumDevice, deviceDescription))) {
    return 1;
  }

  if (mlir::failed(pm.run(*module))) {
    return 1;
  }

  auto outFile = mlir::openOutputFile(outputFilename, &errorMessage);
  if (!outFile) {
    llvm::errs() << errorMessage << "\n";
    return 1;
  }

  // Refuse to dump binary onto a terminal:
  if (binary && llvm::CheckBitcodeOutputToConsole(outFile->os())) {
    return 1;
  }

  switch (compileTo) {
  case Stage::Mlir:
    if (binary) {
      if (mlir::failed(mlir::writeBytecodeToFile(*module, outFile->os()))) {
        llvm::errs() << "failed to write MLIR bytecode\n";
        return 1;
      }
    } else {
      module->print(outFile->os());
    }
    break;
  case Stage::LlvmIr: {
    llvm::LLVMContext llvmContext;
    std::unique_ptr<llvm::Module> llvmModule = mlir::translateModuleToLLVMIR(*module, llvmContext);
    if (!llvmModule) {
      llvm::errs() << "failed to translate the module to LLVM IR\n";
      return 1;
    }
    if (binary) {
      llvm::WriteBitcodeToFile(*llvmModule, outFile->os());
    } else {
      llvmModule->print(outFile->os(), /*AAW=*/nullptr);
    }
    break;
  }
  case Stage::Native: {
    llvm::LLVMContext llvmContext;
    std::unique_ptr<llvm::Module> llvmModule = mlir::translateModuleToLLVMIR(*module, llvmContext);
    if (!llvmModule) {
      llvm::errs() << "failed to translate the module to LLVM IR\n";
      return 1;
    }
    const qcc::NativeCodegenOptions codegenOptions{.binary = binary};
    if (target->emitNative(*llvmModule, static_cast<llvm::raw_pwrite_stream&>(outFile->os()), codegenOptions, *features,
                           numQubitControlLines)) {
      return 1;
    }
    break;
  }
  case Stage::CustomMagic:
    if (mlir::failed(quantumDevice->emitProgram(*module, outFile->os()))) {
      return 1;
    }
    break;
  default:
    llvm_unreachable("--compile-to should always have a value (default value if nothing is set explicitly)");
  }

  outFile->keep(); // otherwise file gets deleted

  return 0;
}
