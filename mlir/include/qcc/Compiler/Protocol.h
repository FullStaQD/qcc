// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// The machine-readable half of the contract between a frontend that drives
// qcc as a subprocess -- the forked Mojo compiler is the first one -- and qcc
// itself. See `mojo/README.md` for the contract as a whole.
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/Support/LLVM.h"

#include "llvm/Support/raw_ostream.h"

namespace qcc {

/// The version of the driver contract this build of qcc implements.
///
/// A frontend states the version it was built against with `--protocol`, and
/// qcc refuses a version it does not speak rather than producing an artifact
/// the caller cannot read. Bump this whenever the meaning of a flag, of the
/// sidecar or of a diagnostic record changes in a way a caller would notice.
inline constexpr unsigned currentProtocolVersion = 1;

/// A diagnostic handler that writes one JSON object per line.
///
/// The line-per-diagnostic form is what lets the caller relay diagnostics as
/// they arrive instead of waiting for qcc to exit; each line is a complete
/// object, so a truncated stream costs at most the last record. Fields are
/// `severity`, `message`, and, when the location names one, `file`, `line`
/// and `column`. Attached notes and the callers of an inlined callsite become
/// `notes`, each of the same shape.
///
/// Locations come from the frontend's own source, so a record points at the
/// `.mojo` line rather than at the exchanged MLIR.
class JsonDiagnosticHandler : public mlir::ScopedDiagnosticHandler {
public:
  JsonDiagnosticHandler(mlir::MLIRContext* context, llvm::raw_ostream& os);
};

/// Writes the entry-point sidecar for `module` to `os`.
///
/// One record per function carrying `qcc.entry_point`, in the order they
/// appear, with the classical signature the caller needs to type a launcher.
/// Types are printed the way MLIR prints them.
void writeEntryPointSidecar(mlir::ModuleOp module, llvm::raw_ostream& os);

} // namespace qcc
