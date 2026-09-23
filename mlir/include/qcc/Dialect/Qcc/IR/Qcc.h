// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/IR/Attributes.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Dialect.h" // IWYU pragma: keep
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/LogicalResult.h" // IWYU pragma: keep

#include <cstdint> // IWYU pragma: keep

//===----------------------------------------------------------------------===//
// Qcc Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/Qcc/IR/QccDialect.h.inc"

//===----------------------------------------------------------------------===//
// Qcc Interfaces
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/Qcc/IR/QccInterfaces.h.inc"

//===----------------------------------------------------------------------===//
// Shared ODS helpers
//===----------------------------------------------------------------------===//

namespace qcc::detail {

/// How one element of a `QCC_ArrayRefParameter` is parsed and printed. Dialect attributes go through the generic field
/// parser (which accepts aliases, the qualified and the stripped form) and print stripped or as an alias.
template <typename T> struct ArrayElement {
  static mlir::FailureOr<T> parse(mlir::AsmParser& parser) { return mlir::FieldParser<T>::parse(parser); }
  static void print(mlir::AsmPrinter& printer, const T& element) { printer.printStrippedAttrOrType(element); }
};

/// Builtin elements attributes have no stripped form: `dense<...> : tensor<...>`.
template <> struct ArrayElement<mlir::DenseElementsAttr> {
  static mlir::FailureOr<mlir::DenseElementsAttr> parse(mlir::AsmParser& parser) {
    mlir::DenseElementsAttr element;
    if (parser.parseAttribute(element)) {
      return mlir::failure();
    }
    return element;
  }
  static void print(mlir::AsmPrinter& printer, mlir::DenseElementsAttr element) { printer << element; }
};

/// Parses `[a, b, c]` for a `QCC_ArrayRefParameter`.
template <typename T> mlir::FailureOr<llvm::SmallVector<T>> parseArray(mlir::AsmParser& parser) {
  llvm::SmallVector<T> elements;
  auto parseElement = [&]() -> mlir::ParseResult {
    mlir::FailureOr<T> element = ArrayElement<T>::parse(parser);
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

/// Prints `[a, b, c]` for a `QCC_ArrayRefParameter`.
template <typename T> void printArray(mlir::AsmPrinter& printer, llvm::ArrayRef<T> elements) {
  printer << "[";
  llvm::interleaveComma(elements, printer, [&](const T& element) { ArrayElement<T>::print(printer, element); });
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
