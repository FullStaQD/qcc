// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/Pass/PassManager.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"

#include <functional>

namespace llvm {
class Module; // Exception to include-by-default: llvm/IR/Module.h is huge; cf. mlir/Target/LLVMIR/Export.h.
} // namespace llvm

namespace qcc {

/// Options controlling native (QISA) code emission for a target.
struct NativeCodegenOptions {
  /// Emit a binary object file instead of textual assembly.
  bool binary = false;
};
// Simplified form of the descriptor-plus-factory pattern in LLVM's
// `llvm/MC/TargetRegistry.h`: `Target` is a flat, non-polymorphic registry
// entry carrying metadata plus a factory (`addLoweringPasses`) for the target's
// behavior. If our implementation must be augmented follow LLVM's lead.

/// Describes a compilation target selectable via `qcc --target=<name>`.
struct Target {
  /// The `--target` value, e.g. "qir".
  llvm::StringRef name;
  /// Human-readable description shown by `--list-targets`.
  llvm::StringRef description;
  /// Assembles the lowering pipeline for this target.
  std::function<void(mlir::PassManager&)> addLoweringPasses;
  /// Emits native code for an already-lowered, LLVM-translated module. Null when
  /// the target has no native backend (e.g. QIR). Returns true on failure.
  std::function<bool(llvm::Module&, llvm::raw_pwrite_stream&, const NativeCodegenOptions&)> emitNative;
};

/// Returns the targets compiled into this build.
llvm::ArrayRef<Target> getTargets();

/// Looks up a target by its name (as expected by `--target`), or returns
/// nullptr if no backend with that name is known.
const Target* lookupTarget(llvm::StringRef name);

} // namespace qcc
