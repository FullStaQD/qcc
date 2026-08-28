// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// hisepq-elf2mem converts a linked HiSEP-Q ELF image into the Verilog
// $readmemh memory file consumed by the opcode simulator (caps-tum/HiSEP-Q-2.0,
// demo/verilator). See qcc/Target/HiSEPQ/Elf2Mem.h for the conversion itself;
// this is a thin CLI wrapper around it. It is the last step of the HiSEP-Q
// pipeline: `qcc --compile-to=native --binary` emits an object file, `ld` links
// it against mlir/lib/Target/HiSEPQ/Scripts/hisepq.ld into an ELF, and
// hisepq-elf2mem turns that ELF into the .mem image (see
// mlir/lib/Target/HiSEPQ/README.md).
//
// ===----------------------------------------------------------------------===//

#include "qcc/Target/HiSEPQ/Elf2Mem.h"

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/WithColor.h"
#include "llvm/Support/raw_ostream.h"

namespace cl = llvm::cl;

/// The name this tool was invoked as; prefixes every diagnostic.
static llvm::StringRef toolName;

/// Reports `err` on stderr as `<tool>: error: '<file>': <message>`.
///
/// This follows the convention of the LLVM binary utilities (compare
/// llvm-readobj's reportError() or llvm-dwarfutil).
static void reportError(llvm::StringRef file, llvm::Error err) {
  // The .mem image goes to stdout by default, so flush it first to avoid
  // interleaving the error message with it.
  llvm::outs().flush();

  if (file == "-") {
    file = "<stdin>";
  }

  llvm::handleAllErrors(llvm::createFileError(file, std::move(err)), [](const llvm::ErrorInfoBase& info) {
    llvm::WithColor::error(llvm::errs(), toolName) << info.message() << "\n";
  });
}

int main(int argc, char** argv) {
  toolName = argv[0]; // NOLINT(cppcoreguidelines-pro-bounds-pointer-arithmetic)

  static cl::OptionCategory elf2memCategory("hisepq-elf2mem options");

  const cl::opt<std::string> inputFilename(cl::Positional, cl::desc("<elf-file>"), cl::Required,
                                           cl::cat(elf2memCategory));
  const cl::opt<std::string> outputFilename("o", cl::desc("Output .mem file"), cl::value_desc("filename"),
                                            cl::init("-"), cl::cat(elf2memCategory));

  cl::ParseCommandLineOptions(argc, argv,
                              "hisepq-elf2mem - convert a HiSEP-Q ELF image into a Verilog $readmemh memory file\n");

  llvm::ErrorOr<std::unique_ptr<llvm::MemoryBuffer>> bufferOrErr = llvm::MemoryBuffer::getFileOrSTDIN(inputFilename);
  if (const std::error_code ec = bufferOrErr.getError()) {
    reportError(inputFilename, llvm::errorCodeToError(ec));
    return 1;
  }

  std::error_code ec;
  llvm::ToolOutputFile outFile(outputFilename, ec, llvm::sys::fs::OF_Text);
  if (ec) {
    reportError(outputFilename, llvm::errorCodeToError(ec));
    return 1;
  }

  if (llvm::Error err = qcc::convertElfToHiSEPQMem(**bufferOrErr, outFile.os())) {
    reportError(inputFilename, std::move(err));
    return 1;
  }

  outFile.keep();
  return 0;
}
