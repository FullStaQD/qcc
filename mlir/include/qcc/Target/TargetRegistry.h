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
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
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

/// A `-mattr` feature.
struct Feature {
  llvm::StringRef name;
  llvm::StringRef description;
};

/// One `-mattr` entry: `+<name>` (or a bare `<name>`) enables a feature, `-<name>` disables it.
struct FeatureFlag {
  llvm::StringRef name;
  bool enable;
};

/// A `-mcpu` processor and the features it enables.
struct Cpu {
  llvm::StringRef name;
  llvm::StringRef description;
  llvm::ArrayRef<llvm::StringRef> features;
  /// Qubit control lines the processor drives unless `-mqcl` overrides it; 0 if the target has none.
  unsigned numQubitControlLines = 0;
};

/// Describes a compilation target selectable via `qcc --target=<name>`.
struct Target {
  /// The `--target` value, e.g. "qir".
  llvm::StringRef name;
  /// Human-readable description shown by `--list-targets`.
  llvm::StringRef description;
  /// The features this target accepts in `-mattr`.
  llvm::ArrayRef<Feature> features;
  /// The processors this target accepts in `-mcpu`; `generic` is the default and must exist.
  llvm::ArrayRef<Cpu> cpus;
  /// Assembles the lowering pipeline for this target, the features and the number of qubit control lines; fails if
  /// they describe no machine.
  std::function<mlir::LogicalResult(mlir::PassManager&, llvm::ArrayRef<FeatureFlag> features,
                                    unsigned numQubitControlLines)>
      addLoweringPasses;
  /// Emits native code for an already-lowered, LLVM-translated module. Null when
  /// the target has no native backend (e.g. QIR). Returns true on failure.
  std::function<bool(llvm::Module&, llvm::raw_pwrite_stream&, const NativeCodegenOptions&,
                     llvm::ArrayRef<FeatureFlag> features, unsigned numQubitControlLines)>
      emitNative;
  /// Whether the lowering ends in the LLVM dialect.
  bool lowersToLLVM = false;
};

/// A (pseudo) target for when we have no control hardware (QISA) to target.
inline constexpr llvm::StringLiteral noTargetName = "none";

/// Looks up a CPU of `target` by its name (as expected by `-mcpu`), or returns nullptr if `target` has none such.
const Cpu* lookupCpu(const Target& target, llvm::StringRef name);

/// The features `cpu` enables, followed by `mattr` (`+<name>,-<name>,...`); fails on names unknown to `target`.
mlir::FailureOr<llvm::SmallVector<FeatureFlag>> parseFeatures(const Target& target, const Cpu& cpu,
                                                              llvm::StringRef mattr);

/// Returns the targets compiled into this build.
llvm::ArrayRef<Target> getTargets();

/// Looks up a target by its name (as expected by `--target`), or returns
/// nullptr if no backend with that name is known.
const Target* lookupTarget(llvm::StringRef name);

} // namespace qcc
