// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Compiler/Compiler.h"
#include "qcc/Compiler/Protocol.h"
#include "qcc/Conversion/MojoResidueToStd/MojoResidueToStd.h"
#include "qcc/Conversion/PrelimHLEPToQCO/PrelimHLEPToQCO.h"
#include "qcc/Dialect/Aux_/IR/Aux_.h"
#include "qcc/Dialect/Jasp/IR/Jasp.h"
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"
#include "qcc/Dialect/PrelimHLEP/Transforms/Passes.h"
#include "qcc/Dialect/QVec/IR/QVec.h"
#include "qcc/Target/TargetRegistry.h"

#include "mqt/Dialect/QC/IR/QCDialect.h"
#include "mqt/Dialect/QCO/IR/QCODialect.h"

#include "mlir/Bytecode/BytecodeWriter.h"
#include "mlir/Conversion/VectorToSCF/VectorToSCF.h"
#include "mlir/Dialect/Arith/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/Transforms/FuncBufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/Transforms/Passes.h"
#include "mlir/Dialect/Func/Extensions/InlinerExtension.h"
#include "mlir/Dialect/Linalg/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/MemRef/Transforms/AllocationOpInterfaceImpl.h"
#include "mlir/Dialect/MemRef/Transforms/Passes.h"
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

#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/SystemUtils.h"
#include "llvm/Support/ToolOutputFile.h"

#include <cstdint>

namespace cl = llvm::cl;

static cl::OptionCategory qccCategory("QCC options");

namespace {
/// The stage to compile to and emit.
enum class Stage : uint8_t { Mlir, LlvmIr, Native };

/// How diagnostics are rendered.
enum class DiagnosticsFormat : uint8_t {
  /// `SourceMgr`'s rendering: the message, the source line and a caret.
  Text,
  /// One JSON object per line, for a frontend that relays them.
  Json,
};

/// What the input file is written in.
enum class Frontend : uint8_t {
  /// qcc's own IR: a well-formed module of dialects qcc knows.
  Mlir,
  /// Elaborated Mojo IR, as `kgen --emit-quantum-kernels` writes it. See
  /// `mojo/README.md`.
  MojoIr,
};
} // namespace

/// Prints the targets compiled into this build.
static void printTargets() {
  llvm::outs() << "Available targets for --target:\n";
  for (const qcc::Target& backend : qcc::getTargets()) {
    llvm::outs() << "  " << backend.name << " - " << backend.description << "\n";
  }
}

/// Writes the entry-point sidecar to `filename`. Returns 0 on success.
static int writeSidecar(mlir::ModuleOp module, llvm::StringRef filename) {
  std::string errorMessage;
  auto file = mlir::openOutputFile(filename, &errorMessage);
  if (!file) {
    llvm::errs() << errorMessage << "\n";
    return 1;
  }
  qcc::writeEntryPointSidecar(module, file->os());
  file->keep();
  return 0;
}

int main(int argc, char** argv) {
  mlir::registerMLIRContextCLOptions();
  mlir::registerPassManagerCLOptions();
  mlir::registerDefaultTimingManagerCLOptions();

  const cl::opt<std::string> inputFilename(cl::Positional, cl::desc("Input-file"), cl::cat(qccCategory));
  const cl::opt<std::string> outputFilename("o", cl::desc("Output-file"), cl::value_desc("filename"), cl::init("-"),
                                            cl::cat(qccCategory));
  const cl::opt<std::string> targetName("target", cl::desc("Target backend to compile for (see --list-targets)"),
                                        cl::init("qir"), cl::value_desc("name"), cl::cat(qccCategory));
  const cl::opt<bool> listTargets("list-targets", cl::desc("List the available --target backends and exit"),
                                  cl::init(false), cl::cat(qccCategory));
  const cl::opt<Stage> compileTo(
      "compile-to", cl::desc("Stage to lower to and emit"), cl::init(Stage::LlvmIr),
      cl::values(clEnumValN(Stage::Mlir, "mlir", "MLIR in the LLVM dialect"),
                 clEnumValN(Stage::LlvmIr, "llvmir", "LLVM IR (QIR for the QIR target)"),
                 clEnumValN(Stage::Native, "native", "Native target code (QISA; requires a target with a backend)")),
      cl::cat(qccCategory));
  const cl::opt<bool> binary("binary", cl::desc("Emit the binary encoding (obj/bytecode/bitcode) instead of text"),
                             cl::init(false), cl::cat(qccCategory));
  const cl::opt<Frontend> frontend(
      "frontend", cl::desc("Language the input file is written in"), cl::init(Frontend::Mlir),
      cl::values(clEnumValN(Frontend::Mlir, "mlir", "qcc's own IR (the default)"),
                 clEnumValN(Frontend::MojoIr, "mojo-ir", "Elaborated Mojo IR from 'kgen --emit-quantum-kernels'")),
      cl::cat(qccCategory));
  const cl::opt<unsigned> protocol(
      "protocol",
      cl::desc("Version of the driver contract the caller speaks; qcc refuses a version it does not implement"),
      cl::init(0), cl::value_desc("version"), cl::cat(qccCategory));
  const cl::opt<DiagnosticsFormat> diagnosticsFormat(
      "diagnostics", cl::desc("How to render diagnostics on stderr"), cl::init(DiagnosticsFormat::Text),
      cl::values(clEnumValN(DiagnosticsFormat::Text, "text", "Source line and caret, for a human (the default)"),
                 clEnumValN(DiagnosticsFormat::Json, "json", "One JSON object per line, for a driving frontend")),
      cl::cat(qccCategory));
  const cl::opt<std::string> entryPointsFilename("emit-entry-points",
                                                 cl::desc("Write the entry-point sidecar (JSON) to this file"),
                                                 cl::value_desc("filename"), cl::cat(qccCategory));
  const cl::opt<bool> verifyOnly("verify-only",
                                 cl::desc("Check the input and exit without lowering it or writing an artifact"),
                                 cl::init(false), cl::cat(qccCategory));

  cl::ParseCommandLineOptions(argc, argv, "qcc - Quantum Compiler Collection\n");

  // The caller states the contract it was built against before anything it
  // sends is interpreted, so a mismatch is one clear line rather than a
  // failure further in, or an artifact the caller cannot read.
  if (protocol != 0 && protocol != qcc::currentProtocolVersion) {
    llvm::errs() << "error: unsupported protocol version " << protocol << " (this qcc speaks "
                 << qcc::currentProtocolVersion << ")\n";
    return 1;
  }

  if (listTargets) {
    printTargets();
    return 0;
  }

  if (inputFilename.empty()) {
    llvm::errs() << "error: no input file specified\n";
    return 1;
  }

  const qcc::Target* target = qcc::lookupTarget(targetName);
  if (target == nullptr) {
    llvm::errs() << "error: unknown target '" << targetName << "' (see --list-targets)\n";
    return 1;
  }

  if (compileTo == Stage::Native && !target->emitNative) {
    llvm::errs() << "error: native output is not supported for --target=" << targetName << "\n";
    return 1;
  }

  mlir::DialectRegistry registry;

  // Register all builtin dialects and their extensions/interfaces:
  mlir::registerAllDialects(registry);

  // Our dialects:
  registry.insert<jasp::JaspDialect, mlir::qc::QCDialect, mlir::qco::QCODialect, qcc::aux::AuxDialect,
                  qcc::prelimhlep::PrelimHLEPDialect, qcc::qvec::QVecDialect>();

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

  // Elaborated Mojo IR carries `kgen`, `pop` and `hlcf` ops that qcc does not
  // know, and is not a well-formed PrelimHLEP program until
  // `mojo-residue-to-std` has run. Both are properties of the exchange
  // format, not of a broken input.
  if (frontend == Frontend::MojoIr) {
    context.allowUnregisteredDialects();
  }

  std::string errorMessage;
  auto inFile = mlir::openInputFile(inputFilename, &errorMessage);
  if (!inFile) {
    llvm::errs() << errorMessage << "\n";
    return 1;
  }

  llvm::SourceMgr sourceMgr;
  sourceMgr.AddNewSourceBuffer(std::move(inFile), llvm::SMLoc());

  // Diagnostics go to stderr either way, so stdout carries only the artifact.
  // The `SourceMgr` handler reads the file a location names -- a `.mojo` file
  // on the Mojo path -- on demand, so both forms report at the frontend's own
  // source position.
  std::optional<mlir::SourceMgrDiagnosticHandler> textDiagnosticHandler;
  std::optional<qcc::JsonDiagnosticHandler> jsonDiagnosticHandler;
  if (diagnosticsFormat == DiagnosticsFormat::Json) {
    jsonDiagnosticHandler.emplace(&context, llvm::errs());
  } else {
    textDiagnosticHandler.emplace(sourceMgr, &context);
  }

  // The Mojo locations name `.mojo` files, which the diagnostic handler above
  // reads on demand, so a qcc diagnostic prints the Mojo line it came from.
  const mlir::ParserConfig parserConfig(&context,
                                        /*verifyAfterParse=*/frontend != Frontend::MojoIr);
  mlir::OwningOpRef<mlir::ModuleOp> module = mlir::parseSourceFile<mlir::ModuleOp>(sourceMgr, parserConfig);
  if (!module) {
    return 1;
  }

  // The Mojo path runs in two stages, because what sits between them is what
  // the contract is written in terms of: the module is a verified PrelimHLEP
  // program whose functions still carry the signatures the caller wrote.
  // `--verify-only` stops there and the sidecar is taken from there.
  if (frontend == Frontend::MojoIr) {
    mlir::PassManager residuePm(&context);
    if (mlir::failed(mlir::applyPassManagerCLOptions(residuePm))) {
      return 1;
    }
    qcc::buildMojoResiduePipeline(residuePm);
    if (mlir::failed(residuePm.run(*module))) {
      return 1;
    }
  }

  if (!entryPointsFilename.empty() && writeSidecar(*module, entryPointsFilename) != 0) {
    return 1;
  }

  if (verifyOnly) {
    return 0;
  }

  mlir::PassManager pm(&context);
  if (mlir::failed(mlir::applyPassManagerCLOptions(pm))) {
    return 1;
  }

  if (frontend == Frontend::MojoIr) {
    // `--compile-to=mlir` stops at QCO, which is what the PrelimHLEP lit
    // tests check; anything further needs the target's lowering.
    qcc::buildMojoLoweringPipeline(pm, compileTo == Stage::Mlir ? nullptr : target);
  } else {
    qcc::buildPipeline(pm, target);
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
    if (target->emitNative(*llvmModule, static_cast<llvm::raw_pwrite_stream&>(outFile->os()), codegenOptions)) {
      return 1;
    }
    break;
  }
  default:
    llvm_unreachable("--compile-to should always have a value (default value if nothing is set explicitly)");
  }

  outFile->keep(); // otherwise file gets deleted

  return 0;
}
