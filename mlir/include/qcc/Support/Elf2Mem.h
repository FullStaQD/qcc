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

/// Converts a linked HiSEP-Q ELF image (riscv32) into the Verilog $readmemh
/// memory file consumed by the opcode simulator (caps-tum/HiSEP-Q-2.0,
/// demo/verilator).
///
/// This function walks the ELF's loadable segments in address order and dumps
/// their bytes as 32-bit hex words, emitting an `@<address>` line whenever a
/// segment does not immediately follow the previous one. Output looks like this
///
/// ```
/// @00000020
/// 00001537
/// 0E050513
/// 000005B7
/// ...
/// ```
llvm::Error convertElfToMem(const llvm::MemoryBuffer& elfBuffer, llvm::raw_ostream& os);

} // namespace qcc
