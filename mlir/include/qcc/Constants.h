// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include <llvm/ADT/StringRef.h>

namespace qcc {

/// A unit attribute to mark a `func.func` as *a* starting point of a quantum program.
static constexpr llvm::StringLiteral entryPointAttrName = "qcc.entry_point";

/// The LLVM dialect attribute whose entries are carried through to the function's LLVM IR attribute list verbatim. This
/// is the name under which the attribute lives on an `llvm.func`. On a `func.func` you have to prepend `llvm.` in order
/// to survive lowering to llvm.
static constexpr llvm::StringLiteral passthroughAttrName = "passthrough";

/// The `passthrough` entry by which QIR marks a function as *a* entry point.
static constexpr llvm::StringLiteral qirEntryPointPassthrough = "entry_point";

} // namespace qcc
