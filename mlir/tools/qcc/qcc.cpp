// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Compiler/Pipeline.h"
#include "qcc/Dialect/Aux_/IR/Aux_.h"
#include "qcc/Dialect/Jasp/IR/Jasp.h"

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
/// The target determines the backend to compile for, the actual passes
/// (pipeline), and the runtime.
enum class Target : uint8_t { Qir, HisepQ };

/// The stage to compile to and emit.
enum class Stage : uint8_t { Mlir, LlvmIr, Native };
} // namespace

int main(int argc, char** argv) {
  mlir::registerMLIRContextCLOptions();
  mlir::registerPassManagerCLOptions();
  mlir::registerDefaultTimingManagerCLOptions();

  const cl::opt<std::string> inputFilename(cl::Positional, cl::desc("Input-file"), cl::Required, cl::cat(qccCategory));
  const cl::opt<std::string> outputFilename("o", cl::desc("Output-file"), cl::value_desc("filename"), cl::init("-"),
                                            cl::cat(qccCategory));
  const cl::opt<Target> target(
      "target", cl::desc("Target pipeline to compile for"), cl::init(Target::Qir),
      cl::values(clEnumValN(Target::Qir, "qir", "QIR (LLVM-based) target"),
                 clEnumValN(Target::HisepQ, "hisep-q", "HiSEP-Q QISA target (not yet implemented)")),
      cl::cat(qccCategory));
  const cl::opt<Stage> compileTo(
      "compile-to", cl::desc("Stage to lower to and emit"), cl::init(Stage::LlvmIr),
      cl::values(clEnumValN(Stage::Mlir, "mlir", "MLIR in the LLVM dialect"),
                 clEnumValN(Stage::LlvmIr, "llvmir", "LLVM IR (QIR for the QIR target)"),
                 clEnumValN(Stage::Native, "native", "Native target code (QISA, not yet implemented)")),
      cl::cat(qccCategory));
  const cl::opt<bool> binary("binary", cl::desc("Emit the binary encoding (obj/bytecode/bitcode) instead of text"),
                             cl::init(false), cl::cat(qccCategory));

  cl::ParseCommandLineOptions(argc, argv, "qcc - quantum compiler collection\n");

  if (target == Target::HisepQ) {
    llvm::errs() << "error: the 'hisep-q' target is not yet implemented\n";
    return 1;
  }

  if (compileTo == Stage::Native) {
    llvm::errs() << "error: the 'native' stage is not yet implemented\n";
    return 1;
  }

  mlir::DialectRegistry registry;

  // Register all builtin dialects and their extensions/interfaces:
  mlir::registerAllDialects(registry);

  // Our dialects:
  registry.insert<jasp::JaspDialect, mlir::qc::QCDialect, qcc::aux::AuxDialect>();

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

  // TODO: Assemble pipeline based on target once a second valid target is added.
  qcc::buildQuantumPipeline(pm);

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
  case Stage::Native:
    llvm_unreachable("the 'native' stage is rejected during option validation");
  default:
    llvm_unreachable("--compile-to should always have a value (default value if nothing is set explicitly)");
  }

  outFile->keep(); // otherwise file gets deleted

  return 0;
}
