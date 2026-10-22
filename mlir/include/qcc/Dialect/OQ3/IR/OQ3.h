// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "qcc/Dialect/Qcc/IR/Qcc.h" // IWYU pragma: keep

#include "mlir/Bytecode/BytecodeOpInterface.h" // IWYU pragma: keep
#include "mlir/IR/Builders.h"                  // IWYU pragma: keep
#include "mlir/IR/BuiltinTypes.h"              // IWYU pragma: keep
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Dialect.h"     // IWYU pragma: keep
#include "mlir/IR/SymbolTable.h" // IWYU pragma: keep
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/InferTypeOpInterface.h" // IWYU pragma: keep
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/APInt.h" // IWYU pragma: keep
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <optional>
#include <variant>

//===----------------------------------------------------------------------===//
// OQ3 Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/OQ3/IR/OQ3Dialect.h.inc"

namespace qcc::oq3 {

/// The resource that statements write which shape the program without having uses (definition markers, includes,
/// pragmas, qubit declarations): it keeps them alive, but aliases with nothing else.
struct ProgramStructureResource : public mlir::SideEffects::Resource::Base<ProgramStructureResource> {
  [[nodiscard]] llvm::StringRef getName() const override { return "oq3.program_structure"; }
};

} // namespace qcc::oq3

//===----------------------------------------------------------------------===//
// OQ3 Types
//===----------------------------------------------------------------------===//

#define GET_TYPEDEF_CLASSES
#include "qcc/Dialect/OQ3/IR/OQ3Types.h.inc"

//===----------------------------------------------------------------------===//
// OQ3 Attributes
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/OQ3/IR/OQ3Enums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/OQ3/IR/OQ3Attrs.h.inc"

//===----------------------------------------------------------------------===//
// OQ3 Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/OQ3/IR/OQ3Ops.h.inc"

//===----------------------------------------------------------------------===//
// Program structure
//===----------------------------------------------------------------------===//

namespace qcc::oq3 {

/// The name of the file that provides the standard gates.
inline constexpr llvm::StringLiteral standardGatesInclude = "stdgates.inc";

/// The version a program without an `OPENQASM` line gets.
inline constexpr unsigned defaultMajorVersion = 3;
inline constexpr unsigned defaultMinorVersion = 1;

inline constexpr unsigned devMinorVersion = 2;
inline constexpr llvm::StringLiteral devSpecDate = "2026-07-27";
inline constexpr llvm::StringLiteral devSpecCommit = "openqasm/openqasm@7fbf9e9";

/// The number and kinds of arguments a gate takes.
struct GateSignature {
  unsigned numParams;
  unsigned numQubits;
};

/// Returns the signature of the built-in gate `name` (`U` or `gphase`), which is defined by the language itself.
std::optional<GateSignature> lookupBuiltinGate(llvm::StringRef name);

/// Returns the signature of the gate `name` of `stdgates.inc`.
std::optional<GateSignature> lookupStandardGate(llvm::StringRef name);

//===----------------------------------------------------------------------===//
// Constant evaluation
//===----------------------------------------------------------------------===//

/// The value of a const expression: an `int` or a `float`.
using ConstantValue = std::variant<int64_t, double>;

/// Evaluates the const expression `value` without changing the IR.
///
/// Fails if `value` is not a const expression, or if its evaluation overflows or divides by zero.
mlir::FailureOr<ConstantValue>
evaluateConstant(mlir::Value value, llvm::function_ref<mlir::InFlightDiagnostic(mlir::Operation*)> emitError = nullptr);

/// Like `evaluateConstant`, but the value must be an integer.
mlir::FailureOr<int64_t>
evaluateConstantInt(mlir::Value value,
                    llvm::function_ref<mlir::InFlightDiagnostic(mlir::Operation*)> emitError = nullptr);

} // namespace qcc::oq3
