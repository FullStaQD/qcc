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

//===----------------------------------------------------------------------===//
// Misc
//===----------------------------------------------------------------------===//

/// Record runtime functions need a label. We do not really support those hence
/// we live with the workaround to always use a dummy label.
static constexpr llvm::StringLiteral qirDummyLabelGlobalSymbolName = ".qir_dummy_label";

//===----------------------------------------------------------------------===//
// QIR runtime functions
//===----------------------------------------------------------------------===//

/// Initializes the execution environment.
///
/// Signature: `void(ptr)`.
///
/// Sets all qubits to a zero-state if they are not dynamically managed. Must be
/// called right at the start of an entry-point.
static constexpr llvm::StringLiteral qirRtInit = "__quantum__rt__initialize";

/// Converts a measurement result to a bool.
///
/// Signature `i1(ptr readonly)`.
static constexpr llvm::StringLiteral qirRtReadResult = "__quantum__rt__read_result";

// TODO: it is unclear how our compiler should handle it.
/// Record a measurement result.
static constexpr llvm::StringLiteral qirRtResultRecordOutput = "__quantum__rt__result_record_output";

/// Adds a boolean value to the generated output.
///
/// Signature: `void(i1,ptr)`.
///
/// The second parameter defines a string label for the result value. Depending
/// on the output schema, the label is included in the output or omitted.
static constexpr llvm::StringLiteral qirRtBoolRecordOutput = "__quantum__rt__bool_record_output";

/// Adds a integer value to the generated output.
///
/// Signature: `void(i64,ptr)`.
///
/// The second parameter defines a string label for the result value. Depending
/// on the output schema, the label is included in the output or omitted.
static constexpr llvm::StringLiteral qirRtIntRecordOutput = "__quantum__rt__int_record_output";

//===----------------------------------------------------------------------===//
// QIR quantum instruction set (QIS)
//===----------------------------------------------------------------------===//

// TODO: This is a hardcoded QIS, we need to query it from the device in the future.

/// Z-Basis measurement (irreversible).
static constexpr llvm::StringLiteral qirQisMZ = "__quantum__qis__mz__body";

/// Reset a qubit to the |0⟩ state (irreversible).
static constexpr llvm::StringLiteral qirQisReset = "__quantum__qis__reset__body";

/// Single target hadamard gate.
static constexpr llvm::StringLiteral qirQisH = "__quantum__qis__h__body";

/// Single target X gate.
static constexpr llvm::StringLiteral qirQisX = "__quantum__qis__x__body";

/// CX gate controlled on first qubit/ptr.
static constexpr llvm::StringLiteral qirQisCX = "__quantum__qis__cx__body";

/// Rotation around the Z-axis where the first parameter (a double-precision float) is the angle.
static constexpr llvm::StringLiteral qirQisRZ = "__quantum__qis__rz__body";

/// Single target S gate.
static constexpr llvm::StringLiteral qirQisS = "__quantum__qis__s__body";

/// Single target S† gate.
static constexpr llvm::StringLiteral qirQisSdg = "__quantum__qis__s__adj";

/// Single target T gate.
static constexpr llvm::StringLiteral qirQisT = "__quantum__qis__t__body";

/// Single target T† gate.
static constexpr llvm::StringLiteral qirQisTdg = "__quantum__qis__t__adj";

} // namespace qcc
