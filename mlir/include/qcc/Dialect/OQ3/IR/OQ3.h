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
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"     // IWYU pragma: keep
#include "mlir/IR/BuiltinOps.h"   // IWYU pragma: keep
#include "mlir/IR/BuiltinTypes.h" // IWYU pragma: keep
#include "mlir/IR/Dialect.h"      // IWYU pragma: keep
#include "mlir/IR/SymbolTable.h"  // IWYU pragma: keep
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include "llvm/ADT/APInt.h" // IWYU pragma: keep
#include "llvm/ADT/StringRef.h"

#include <cstdint>  // IWYU pragma: keep
#include <optional> // IWYU pragma: keep

//===----------------------------------------------------------------------===//
// OQ3 Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/OQ3/IR/OQ3Dialect.h.inc"

namespace qcc::oq3 {

/// The resource that operations write which carry source text without effect on the program (comments, pragmas,
/// declarations, ...): it keeps them alive, but aliases with nothing else.
struct SourceTextResource : public mlir::SideEffects::Resource::Base<SourceTextResource> {
  llvm::StringRef getName() const override { return "oq3.source_text"; }
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

/// Whether `type` is `!oq3.unknown`, or a sized type whose size is unknown (also as the element of a `!qcc.ref`).
bool isUnknownOrHasUnknownSize(mlir::Type type);

/// Whether `text` is one complete comment, markers included: a line comment `// ...` or a block comment `/* ... */`.
bool isValidCommentText(llvm::StringRef text);

/// Whether `text` is one or more comments that follow each other on one line, separated by spaces, as in
/// `/* a */ // b`. This is the text of `oq3.trailing_comment`.
bool isValidTrailingCommentText(llvm::StringRef text);

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

/// The value of a const expression.
struct ConstantValue {
  enum class Kind : uint8_t { Int, Float };
  Kind kind;
  int64_t intValue = 0;
  double floatValue = 0.0;

  static ConstantValue getInt(int64_t value) { return {.kind = Kind::Int, .intValue = value}; }
  static ConstantValue getFloat(double value) { return {.kind = Kind::Float, .floatValue = value}; }
  [[nodiscard]] bool isInt() const { return kind == Kind::Int; }
};

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
