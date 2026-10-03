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
#include "mlir/Pass/PassManager.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/LogicalResult.h"
#include "llvm/Support/raw_ostream.h"

#include <functional>

namespace qcc {

// The counterpart of `Target` (see `qcc/Target/TargetRegistry.h`) for the other axis of a compilation: a target is
// the control electronics the code is generated for (a QISA), a quantum device is the quantum hardware the gates are
// lowered for.

/// Describes a kind of quantum device selectable via `qcc --quantum-device=<name>`.
///
/// TODO: Our naming conventions are not ideal. On the commandline we just call it "quantum device". We also have
/// "MagicDevice" which is not exactly a quantum device but a concrete instance. "quantum target" could be another
/// option but we might want to rename the --target to --control-target then.
struct QuantumDeviceKind {
  /// The `--quantum-device` value, e.g. "magic".
  llvm::StringRef name;
  /// Human-readable description.
  llvm::StringRef description;
  /// Assembles the pipeline that lowers the gates of a program for this kind of device. It runs after the frontend
  /// lowering and before the lowering of the target. The device itself is described by the module's `qcc.device`.
  std::function<void(mlir::PassManager&)> addLoweringPasses;
  /// Prints the lowered module as a device-level program. Null when the device has no such format.
  std::function<llvm::LogicalResult(mlir::ModuleOp, llvm::raw_ostream&)> emitProgram;
};

/// The name of the entry that stands for "no quantum device": no device-specific lowering.
inline constexpr llvm::StringLiteral noQuantumDeviceName = "none";

/// Returns the quantum devices compiled into this build.
llvm::ArrayRef<QuantumDeviceKind> getQuantumDeviceKinds();

/// Looks up a quantum device by its name (as expected by `--quantum-device`), or returns nullptr if no device with
/// that name is known.
const QuantumDeviceKind* lookupQuantumDeviceKind(llvm::StringRef name);

} // namespace qcc
