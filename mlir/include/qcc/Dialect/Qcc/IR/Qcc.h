// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/Bytecode/BytecodeOpInterface.h" // IWYU pragma: keep
#include "mlir/IR/Attributes.h"
#include "mlir/IR/Builders.h" // IWYU pragma: keep
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypeInterfaces.h" // IWYU pragma: keep
#include "mlir/IR/Dialect.h"               // IWYU pragma: keep
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h" // IWYU pragma: keep
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Interfaces/SideEffectInterfaces.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/LogicalResult.h" // IWYU pragma: keep

#include <cassert>
#include <cstdint> // IWYU pragma: keep

//===----------------------------------------------------------------------===//
// Qcc Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/Qcc/IR/QccDialect.h.inc"

//===----------------------------------------------------------------------===//
// Qcc Types
//===----------------------------------------------------------------------===//

#define GET_TYPEDEF_CLASSES
#include "qcc/Dialect/Qcc/IR/QccTypes.h.inc"

namespace qcc {

/// Whether `type` is `!qcc.qubit` or a vector of them.
bool isQubitOrQubitVector(mlir::Type type);

} // namespace qcc

//===----------------------------------------------------------------------===//
// Qcc Interfaces
//===----------------------------------------------------------------------===//

namespace qcc::detail {

/// Verifies the lanes of `op`, which implements the `QubitLaneOpInterface`: every lane has both ends and both are of
/// the same qubit type, the qubit results are the leading results, and there is no qubit outside the lanes.
llvm::LogicalResult verifyQubitLaneOpInterface(mlir::Operation* op);

} // namespace qcc::detail

#include "qcc/Dialect/Qcc/IR/QccAttrInterfaces.h.inc"
#include "qcc/Dialect/Qcc/IR/QccOpInterfaces.h.inc"

//===----------------------------------------------------------------------===//
// Qcc Traits
//===----------------------------------------------------------------------===//

namespace qcc {

/// Verifies that `op` sits directly in a single-block function without qubit arguments and results, and that the
/// qubits `op` touches are used at most once. See the dialect description on affine qubit values.
llvm::LogicalResult verifySingleUseQubits(mlir::Operation* op);

/// Corresponds to `Qcc_SingleUseQubits` in tablegen. An op trait mixin in the style of `mlir::OpTrait`, hence the
/// public constructor.
template <typename ConcreteType>
class SingleUseQubits // NOLINT(bugprone-crtp-constructor-accessibility)
    : public mlir::OpTrait::TraitBase<ConcreteType, SingleUseQubits> {
public:
  static llvm::LogicalResult verifyTrait(mlir::Operation* op) { return verifySingleUseQubits(op); }
};

} // namespace qcc

//===----------------------------------------------------------------------===//
// Qcc Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/Qcc/IR/QccOps.h.inc"

//===----------------------------------------------------------------------===//
// Shared ODS helpers
//===----------------------------------------------------------------------===//

namespace qcc::detail {

/// Parses `[a, b, c]` for a `QCC_ArrayRefParameter`. The generic field parser takes an element as an alias, in the
/// qualified and in the stripped form.
template <typename T> mlir::FailureOr<llvm::SmallVector<T>> parseArray(mlir::AsmParser& parser) {
  llvm::SmallVector<T> elements;
  auto parseElement = [&]() -> mlir::ParseResult {
    mlir::FailureOr<T> element = mlir::FieldParser<T>::parse(parser);
    if (mlir::failed(element)) {
      return mlir::failure();
    }
    elements.push_back(*element);
    return mlir::success();
  };
  if (parser.parseCommaSeparatedList(mlir::AsmParser::Delimiter::Square, parseElement)) {
    return mlir::failure();
  }
  return elements;
}

/// Prints `[a, b, c]` for a `QCC_ArrayRefParameter`, each element stripped or as an alias.
template <typename T> void printArray(mlir::AsmPrinter& printer, llvm::ArrayRef<T> elements) {
  printer << "[";
  llvm::interleaveComma(elements, printer, [&](const T& element) { printer.printStrippedAttrOrType(element); });
  printer << "]";
}

} // namespace qcc::detail

namespace qcc {

/// Reads the device description from a device file.
///
/// A device file is a minimal module that carries only the `qcc.device` attribute, so that attribute aliases work:
/// ```mlir
/// #trap = #magic.trap<...>
/// module attributes {qcc.device = #magic.device<..., traps = [#trap, #trap]>} {}
/// ```
/// Returns the (verified) `qcc.device` attribute. Emits a diagnostic and fails if the file cannot be read or parsed,
/// or if it carries no `qcc.device` attribute.
mlir::FailureOr<mlir::Attribute> parseDeviceFile(llvm::StringRef path, mlir::MLIRContext& ctx);

} // namespace qcc
