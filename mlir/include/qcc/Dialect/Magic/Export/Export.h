// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/IR/BuiltinOps.h"

#include "llvm/Support/LogicalResult.h"
#include "llvm/Support/raw_ostream.h"

namespace qcc::magic {

/// Prints the magic program of `module` to `os` in the text format the device takes today: a header that describes the
/// traps and the result bits, one statement per native instruction, and the measurement of every ion at the end.
///
/// This is a plain translation of a finished program. The module carries the device (`qcc.device`) and holds exactly
/// one entry point (`qcc.entry_point`): the program, a function with a `magic.init` that passed `magic-verify`. Other
/// functions are ignored. The format knows less than the IR, so the program additionally has to
///
/// - number its ions 0..N-1 trap by trap (`magic-compact-ion-ids`), and
/// - measure every ion and record every result (`magic-measure-and-record-garbage`).
llvm::LogicalResult exportProgram(mlir::ModuleOp module, llvm::raw_ostream& os);

} // namespace qcc::magic
