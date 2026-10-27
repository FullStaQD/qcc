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
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypeInterfaces.h" // IWYU pragma: keep
#include "mlir/IR/Dialect.h"               // IWYU pragma: keep
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h" // IWYU pragma: keep
#include "mlir/IR/TypeRange.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/LogicalResult.h" // IWYU pragma: keep

#include <cassert>
#include <cstdint> // IWYU pragma: keep
#include <optional>

//===----------------------------------------------------------------------===//
// Qcc Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/Qcc/IR/QccDialect.h.inc"

//===----------------------------------------------------------------------===//
// Qcc Types
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/Qcc/IR/QccTypeInterfaces.h.inc"

#define GET_TYPEDEF_CLASSES
#include "qcc/Dialect/Qcc/IR/QccTypes.h.inc"

namespace qcc {

/// Whether `type` is `!qcc.qubit` or a vector of them.
bool isQubitOrQubitVector(mlir::Type type);

/// Whether `type` is the type of classical values: a type with the `ClassicalTypeInterface`, a builtin integer,
/// floating-point, `index`, or `complex` type, or a tensor or vector of classical elements.
bool isClassicalType(mlir::Type type);

} // namespace qcc

//===----------------------------------------------------------------------===//
// Qcc Attributes
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/Qcc/IR/QccEnums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/Qcc/IR/QccAttrs.h.inc"

//===----------------------------------------------------------------------===//
// Qcc Resources
//===----------------------------------------------------------------------===//

namespace qcc {

/// Side-effect resource for qubits that operations access by reference. An operation that acts on a qubit through a
/// reference reads and writes this resource, `qcc.alloc` allocates in it, and `qcc.dealloc` frees in it.
///
/// Like every resource, it is part of the default resource: effects on qubits may conflict with effects on the default
/// resource, e.g. with a `memref.load`. It is disjoint from other resources, e.g. `oq3::ProgramStructureResource`.
struct QubitResource : public mlir::SideEffects::Resource::Base<QubitResource> {
  [[nodiscard]] llvm::StringRef getName() const override { return "qcc.qubits"; }
};

} // namespace qcc

//===----------------------------------------------------------------------===//
// Gates
//===----------------------------------------------------------------------===//

namespace qcc {

/// Parses the types of a gate (custom directive `GateTypes`): `[<angle type>, ]<qubit type>`.
mlir::ParseResult parseGateTypes(mlir::OpAsmParser& parser, llvm::SmallVectorImpl<mlir::Type>& paramTypes,
                                 llvm::ArrayRef<mlir::OpAsmParser::UnresolvedOperand> params, mlir::Type& qubitType);

/// Prints the types of a gate (custom directive `GateTypes`): `[<angle type>, ]<qubit type>`.
void printGateTypes(mlir::OpAsmPrinter& printer, mlir::Operation* op, mlir::TypeRange paramTypes,
                    mlir::OperandRange params, mlir::Type qubitType);

} // namespace qcc

namespace qcc::detail {

/// Verifies that `op`, a single gate of `kind`, takes as many params as given by `params`.
llvm::LogicalResult verifyGateParams(mlir::Operation* op, SingleGateKind kind, mlir::ValueRange params);
/// Verifies that `op`, a pair gate of `kind`, takes as many params as given by `params`.
llvm::LogicalResult verifyGateParams(mlir::Operation* op, PairGateKind kind, mlir::ValueRange params);

} // namespace qcc::detail

//===----------------------------------------------------------------------===//
// Qcc Interfaces
//===----------------------------------------------------------------------===//

namespace qcc::detail {

/// Returns how many of the leading `types` are qubits or vectors of qubits.
unsigned getNumLeadingQubits(mlir::TypeRange types);

/// Verifies the lanes of `op`, which implements the `QubitLaneOpInterface`: the qubits are the leading operands and
/// the leading results, there are equally many of both, and operand `i` has the type of result `i`.
llvm::LogicalResult verifyQubitLaneOpInterface(mlir::Operation* op);

} // namespace qcc::detail

#include "qcc/Dialect/Qcc/IR/QccAttrInterfaces.h.inc"
#include "qcc/Dialect/Qcc/IR/QccOpInterfaces.h.inc"

namespace qcc {

/// Walks back from the qubit operand `qubitUse` along its lane, through `QubitLaneOpInterface` ops. Returns the value
/// where the walk stops: a block argument, or a result of an op that is not a lane op.
///
/// This holds when `qubitUse` sits directly in a verified function or qubit scope, where a lane never leaves its block.
/// On other IR, the walk also stops at a lane op in another block or after the op it feeds, instead of asserting: a
/// verifier may call it before dominance is verified.
mlir::Value walkBackAlongLane(mlir::OpOperand& qubitUse);

} // namespace qcc

//===----------------------------------------------------------------------===//
// Qcc Traits
//===----------------------------------------------------------------------===//

namespace qcc {

namespace detail {
llvm::LogicalResult verifyNoMultiUseQubits(mlir::Operation* op);
llvm::LogicalResult verifyQubitScope(mlir::Operation* op);
} // namespace detail

/// Corresponds to `Qcc_NoMultiUseQubits` in tablegen.
///
/// Imposes the following constraints:
/// - The operation sits directly in a qubit scope (see `QubitScope`) or in a function (`func.func` or any other
///   `FunctionOpInterface` operation). Such a function has a single block and no qubits among its arguments and
///   results.
/// - Each scalar qubit result of the operation is used at most once. A vector result may be used several times, to
///   take it apart (`vector.extract`).
/// - Each qubit operand of the operation, scalar or vector, has no other use. For a vector operand, this also rejects
///   taking elements out of it (`vector.extract`): stricter than `QubitType` if the taken-out qubit is never consumed.
///
/// TODO: Counting uses fits the affine discipline of `QubitType` only where every use consumes, as for scalar qubits.
/// `vector.extract` uses a vector without consuming it, so violations inside a vector, e.g. taking the same element out
/// twice and consuming both, go unnoticed. Undecided how to close the gap; probably a check pass, with only the
/// simplest violations caught here.
template <typename ConcreteType>
class NoMultiUseQubits // NOLINT(bugprone-crtp-constructor-accessibility)
    : public mlir::OpTrait::TraitBase<ConcreteType, NoMultiUseQubits> {
public:
  static llvm::LogicalResult verifyTrait(mlir::Operation* op) { return detail::verifyNoMultiUseQubits(op); }
};

/// Corresponds to `Qcc_QubitScopeImpl` in tablegen.
///
/// Imposes the following constraints on the regions of a qubit scope:
/// - No operation in them, at any depth, uses a qubit (scalar or vector) from outside the scope. Qubits enter only as
///   arguments of the entry blocks, the *bindings*.
/// - Each scalar qubit binding is used at most once.
/// The `SingleBlock` trait, verified first, ensures that each region has at most one block.
template <typename ConcreteType>
class QubitScope // NOLINT(bugprone-crtp-constructor-accessibility)
    : public mlir::OpTrait::TraitBase<ConcreteType, QubitScope> {
public:
  static llvm::LogicalResult verifyTrait(mlir::Operation* op) { return detail::verifyQubitScope(op); }
};

} // namespace qcc

//===----------------------------------------------------------------------===//
// Qcc Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/Qcc/IR/QccOps.h.inc"

namespace qcc {

/// Returns the index of the static qubit that `ref` names if `ref` is a result of `qcc.static_ref`, otherwise
/// `std::nullopt`. Two references with the same index name the same qubit.
std::optional<int64_t> getStaticRefIndex(mlir::Value ref);

} // namespace qcc

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

/// Whether `op` is an entry point of a program: a function marked `qcc.entry_point`.
bool isEntryPoint(mlir::Operation* op);

/// Returns the entry points of `module` in order. A module may have any number of them.
llvm::SmallVector<mlir::FunctionOpInterface> getEntryPoints(mlir::ModuleOp module);

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
