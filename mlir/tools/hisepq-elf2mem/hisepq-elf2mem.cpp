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

#include "llvm/Support/CommandLine.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/ToolOutputFile.h"

namespace cl = llvm::cl;

int main(int argc, char** argv) {
  static cl::OptionCategory elf2memCategory("hisepq-elf2mem options");

  const cl::opt<std::string> inputFilename(cl::Positional, cl::desc("<elf-file>"), cl::Required,
                                           cl::cat(elf2memCategory));
  const cl::opt<std::string> outputFilename("o", cl::desc("Output .mem file"), cl::value_desc("filename"),
                                            cl::init("-"), cl::cat(elf2memCategory));

  // FIXME: this message looks a bit technical (especially the "$readmemh" thingy).
  cl::ParseCommandLineOptions(argc, argv,
                              "hisepq-elf2mem - convert a HiSEP-Q ELF image into a Verilog $readmemh memory file\n");

  llvm::ErrorOr<std::unique_ptr<llvm::MemoryBuffer>> bufferOrErr = llvm::MemoryBuffer::getFileOrSTDIN(inputFilename);
  if (std::error_code ec = bufferOrErr.getError()) {
    llvm::errs() << inputFilename << ": " << ec.message() << "\n";
    return 1;
  }

  // FIXME: on error reporting: is there a better way than just doing llvm::errs()?

  std::error_code ec;
  llvm::ToolOutputFile outFile(outputFilename, ec, llvm::sys::fs::OF_Text);
  if (ec) {
    llvm::errs() << outputFilename << ": " << ec.message() << "\n";
    return 1;
  }

  if (auto err = qcc::convertElfToHiSEPQMem(**bufferOrErr, outFile.os())) {
    llvm::errs() << inputFilename << ": " << llvm::toString(std::move(err)) << "\n";
    return 1;
  }

  outFile.keep();
  return 0;
}
