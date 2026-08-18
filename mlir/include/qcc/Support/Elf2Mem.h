// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "llvm/Support/Error.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"

namespace qcc {

/// Converts a linked HiSEP-Q ELF image (32-bit little-endian, e.g. riscv32) into the Verilog
/// $readmemh memory file consumed by the opcode simulator (caps-tum/HiSEP-Q-2.0, demo/verilator).
///
/// This program walks the ELF's PT_LOAD segments in address order and dumps their bytes as 32-bit
/// hex words, emitting an `@<address>` line whenever a segment does not immediately follow the
/// previous one. Getting the memory layout right (entry code at the hardware's boot address,
/// sensible section placement) is the linker script's job (see mlir/tools/loader/hisepq.ld).
llvm::Error convertElfToMem(const llvm::MemoryBuffer& elfBuffer,
                            llvm::raw_ostream& os); // FIXME: check the llvm::Error return type.

} // namespace qcc
