// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/OQ3/IR/OQ3.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h" // IWYU pragma: keep
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"

#include "llvm/ADT/STLExtras.h" // IWYU pragma: keep
#include "llvm/ADT/StringSwitch.h"

#include <cstdint>
#include <optional>

using namespace mlir;
using namespace qcc;
using namespace qcc::oq3;

//===----------------------------------------------------------------------===//
// Custom directives
//===----------------------------------------------------------------------===//

/// Parses the types of an `oq3.binary`: `T` if both operands and the result have type `T`, else `(L, R) -> T`.
static ParseResult parseBinaryTypes(OpAsmParser& parser, Type& lhsType, Type& rhsType, Type& resultType) {
  if (failed(parser.parseOptionalLParen())) {
    if (parser.parseType(resultType)) {
      return failure();
    }
    lhsType = rhsType = resultType;
    return success();
  }
  return failure(parser.parseType(lhsType) || parser.parseComma() || parser.parseType(rhsType) ||
                 parser.parseRParen() || parser.parseArrow() || parser.parseType(resultType));
}

/// Prints the types of an `oq3.binary`, see `parseBinaryTypes`.
static void printBinaryTypes(OpAsmPrinter& printer, Operation* /*op*/, Type lhsType, Type rhsType, Type resultType) {
  if (lhsType == resultType && rhsType == resultType) {
    printer << resultType;
    return;
  }
  printer << "(" << lhsType << ", " << rhsType << ") -> " << resultType;
}

#define GET_OP_CLASSES
#include "qcc/Dialect/OQ3/IR/OQ3Ops.cpp.inc"

//===----------------------------------------------------------------------===//
// Shared verification
//===----------------------------------------------------------------------===//

/// Fails unless `op` is a statement of the entry body.
static LogicalResult verifyInEntryBody(Operation* op) {
  if (!isEntryPoint(op->getParentOp())) {
    return op->emitOpError() << "is only valid directly in the entry function ('"
                             << QccDialect::EntryPointAttrHelper::getNameStr() << "')";
  }
  return success();
}

/// Whether `type` is the type of an integer index or size.
static bool isUnsizedIntegerOrUnknown(Type type) { return isa<UnsizedIntType, UnknownType>(type); }

/// Verifies the designator of a declaration against `size`, the size that the declared type holds.
static LogicalResult verifyDesignator(Operation* op, Value designator, int64_t size) {
  const Type type = designator.getType();
  if (!isUnsizedIntegerOrUnknown(type)) {
    return op->emitOpError() << "designator must be an unsized integer or unknown type, got " << type;
  }
  if (isa<UnknownType>(type)) {
    if (!ShapedType::isDynamic(size)) {
      return op->emitOpError() << "designator depends on an unresolved name, so the size must be '?'";
    }
    return success();
  }
  const FailureOr<int64_t> value = evaluateConstantInt(designator);
  if (failed(value)) {
    return op->emitOpError() << "designator must be a constant expression";
  }
  if (ShapedType::isDynamic(size) || *value != size) {
    return op->emitOpError() << "designator evaluates to " << *value << ", but the type has size "
                             << (ShapedType::isDynamic(size) ? "?" : std::to_string(size));
  }
  return success();
}

/// Verifies a constant `index` into something of `size` elements: `-size <= index < size`.
static LogicalResult verifyIndex(Operation* op, Value index, int64_t size) {
  if (!isUnsizedIntegerOrUnknown(index.getType())) {
    return op->emitOpError() << "index must be an unsized integer or unknown type, got " << index.getType();
  }
  if (ShapedType::isDynamic(size)) {
    return success();
  }
  const FailureOr<int64_t> value = evaluateConstantInt(index);
  if (succeeded(value) && (*value < -size || *value >= size)) {
    return op->emitOpError() << "index " << *value << " is out of range for size " << size;
  }
  return success();
}

/// Returns the size of the quantum register type `type`, or nullopt if it is no register.
static std::optional<int64_t> getRegisterSize(Type type) {
  if (auto reg = dyn_cast<QRegType>(type)) {
    return reg.getSize();
  }
  return std::nullopt;
}

//===----------------------------------------------------------------------===//
// Program structure and directives
//===----------------------------------------------------------------------===//

LogicalResult DefinedOp::verify() { return verifyInEntryBody(*this); }

LogicalResult IncludeOp::verify() {
  if (failed(verifyInEntryBody(*this))) {
    return failure();
  }
  const StringRef path = getPath();
  if (path.empty() || path.find_first_of("\r\n\t") != StringRef::npos || (path.contains('"') && path.contains('\''))) {
    return emitOpError() << "path must be non-empty, a single line, and not contain both kinds of quotes";
  }
  return success();
}

LogicalResult CommentOp::verify() {
  if (!isValidCommentText(getText())) {
    return emitOpError() << "text must be one complete comment ('// ...' or '/* ... */'), got '" << getText() << "'";
  }
  if (getHeader()) {
    if (failed(verifyInEntryBody(*this))) {
      return failure();
    }
    for (Operation* previous = (*this)->getPrevNode(); previous != nullptr; previous = previous->getPrevNode()) {
      auto comment = dyn_cast<CommentOp>(previous);
      if (!comment || !comment.getHeader()) {
        return emitOpError() << "is a header comment, so it must precede all other statements";
      }
    }
  }
  return success();
}

LogicalResult PragmaOp::verify() {
  const StringRef text = getText();
  if (text.empty() || text.find_first_of("\r\n") != StringRef::npos || text.front() == ' ' || text.front() == '\t') {
    return emitOpError() << "text must be a non-empty single line without leading whitespace";
  }
  return verifyInEntryBody(*this);
}

//===----------------------------------------------------------------------===//
// Declarations and storage
//===----------------------------------------------------------------------===//

LogicalResult QubitDeclOp::verify() {
  if (failed(verifyInEntryBody(*this))) {
    return failure();
  }
  const std::optional<int64_t> size = getRegisterSize(getType());
  if (!getDesignator()) {
    return success();
  }
  if (!size) {
    return emitOpError() << "declares a single qubit, so it takes no designator";
  }
  return verifyDesignator(*this, getDesignator(), *size);
}

LogicalResult DeclareOp::verify() {
  const Type elementType = getType().getElementType();
  if (!isa<BitType, BitsType>(elementType)) {
    return emitOpError() << "declares a variable of type " << elementType
                         << ", but only 'bit' and 'bit[n]' variables are supported yet";
  }
  if (getInit() && getInit().getType() != elementType) {
    return emitOpError() << "initial value of type " << getInit().getType() << " does not match the variable type "
                         << elementType;
  }
  if (!getDesignator()) {
    return success();
  }
  auto bits = dyn_cast<BitsType>(elementType);
  if (!bits) {
    return emitOpError() << "declares a single bit, so it takes no designator";
  }
  return verifyDesignator(*this, getDesignator(), bits.getSize());
}

LogicalResult SubrefOp::verify() {
  auto bits = dyn_cast<BitsType>(getRef().getType().getElementType());
  if (!bits) {
    return emitOpError() << "can only index a bit register, got " << getRef().getType();
  }
  if (!isa<BitType>(getType().getElementType())) {
    return emitOpError() << "a bit of a bit register has type '!qcc.ref<!oq3.bit>', got " << getType();
  }
  return verifyIndex(*this, getIndex(), bits.getSize());
}

//===----------------------------------------------------------------------===//
// Qubit aliasing
//===----------------------------------------------------------------------===//

LogicalResult QubitIndexOp::verify() {
  return verifyIndex(*this, getIndex(), getRegisterSize(getReg().getType()).value_or(ShapedType::kDynamic));
}

//===----------------------------------------------------------------------===//
// Expressions
//===----------------------------------------------------------------------===//

LogicalResult ConstantOp::verify() {
  if (!isa<IntLiteralAttr, FloatLiteralAttr, BitstringAttr>(getValue())) {
    return emitOpError() << "unsupported literal " << getValue();
  }
  if (getRadix() && !isa<IntLiteralAttr>(getValue())) {
    return emitOpError() << "only integer literals have a radix";
  }
  return success();
}

/// Whether `type` supports arithmetic.
static bool isArithmetic(Type type) { return isa<UnsizedIntType, UnsizedFloatType, AngleType>(type); }

LogicalResult UnaryOp::verify() {
  if (!isArithmetic(getType()) && !isa<UnknownType>(getType())) {
    return emitOpError() << "unsupported operand type " << getType();
  }
  return success();
}

LogicalResult BinaryOp::verify() {
  const Type lhsType = getLhs().getType();
  const Type rhsType = getRhs().getType();
  const Type resultType = getType();

  if (isa<UnknownType>(lhsType) || isa<UnknownType>(rhsType)) {
    if (!isa<UnknownType>(resultType)) {
      return emitOpError() << "has an operand of unknown type, so its result type must be '!oq3.unknown'";
    }
    return success();
  }

  const BinaryKind kind = getKind();
  const bool isScaling = kind == BinaryKind::Mul || kind == BinaryKind::Div;
  if (lhsType == resultType && rhsType == resultType && isArithmetic(resultType)) {
    if (isa<AngleType>(resultType) && isScaling) {
      return emitOpError() << "cannot " << (kind == BinaryKind::Mul ? "multiply" : "divide")
                           << " two angles; scale an angle by an integer instead";
    }
    return success();
  }

  // Scaling an angle by an integer.
  const bool lhsAngle = isa<AngleType>(lhsType);
  const bool rhsAngle = isa<AngleType>(rhsType);
  const bool lhsInt = isa<UnsizedIntType>(lhsType);
  const bool rhsInt = isa<UnsizedIntType>(rhsType);
  if (isa<AngleType>(resultType) && ((kind == BinaryKind::Mul && ((lhsAngle && rhsInt) || (lhsInt && rhsAngle))) ||
                                     (kind == BinaryKind::Div && lhsAngle && rhsInt))) {
    return success();
  }

  return emitOpError() << "unsupported operand types " << lhsType << " and " << rhsType << " with result type "
                       << resultType << " for '" << stringifyBinaryKind(kind) << "'";
}

LogicalResult CastOp::verify() {
  const Type from = getInput().getType();
  const Type to = getType();
  const bool supported = (isa<UnsizedIntType>(from) && isa<UnsizedFloatType, BitType>(to)) ||
                         (isa<UnsizedFloatType>(from) && isa<AngleType>(to));
  if (!supported) {
    return emitOpError() << "unsupported cast from " << from << " to " << to;
  }
  return success();
}

LogicalResult MeasureOp::verify() {
  const Type qubitsType = getQubits().getType();
  const Type resultType = getType();
  const bool matches = TypeSwitch<Type, bool>(qubitsType)
                           .Case([&](QubitRefType) { return isa<BitType>(resultType); })
                           .Case([&](QRegType reg) {
                             auto bits = dyn_cast<BitsType>(resultType);
                             return bits && bits.getSize() == reg.getSize();
                           })
                           .Case([&](UnknownType) { return isa<UnknownType>(resultType); })
                           .Default(false);
  if (!matches) {
    return emitOpError() << "measuring " << qubitsType << " cannot yield " << resultType
                         << " (a qubit yields a bit, n qubits yield n bits)";
  }
  return success();
}

//===----------------------------------------------------------------------===//
// Quantum instructions
//===----------------------------------------------------------------------===//

std::optional<GateSignature> qcc::oq3::lookupBuiltinGate(StringRef name) {
  return llvm::StringSwitch<std::optional<GateSignature>>(name)
      .Case("U", GateSignature{.numParams = 3, .numQubits = 1})
      .Case("gphase", GateSignature{.numParams = 1, .numQubits = 0})
      .Default(std::nullopt);
}

std::optional<GateSignature> qcc::oq3::lookupStandardGate(StringRef name) {
  using Sig = GateSignature;
  return llvm::StringSwitch<std::optional<GateSignature>>(name)
      .Case("p", Sig{.numParams = 1, .numQubits = 1})
      .Cases({"x", "y", "z", "h", "s", "sdg", "t", "tdg", "sx", "id"}, Sig{.numParams = 0, .numQubits = 1})
      .Cases({"rx", "ry", "rz", "phase", "u1"}, Sig{.numParams = 1, .numQubits = 1})
      .Case("u2", Sig{.numParams = 2, .numQubits = 1})
      .Case("u3", Sig{.numParams = 3, .numQubits = 1})
      .Cases({"cx", "cy", "cz", "ch", "swap", "CX"}, Sig{.numParams = 0, .numQubits = 2})
      .Cases({"cp", "crx", "cry", "crz", "cphase"}, Sig{.numParams = 1, .numQubits = 2})
      .Case("cu", Sig{.numParams = 4, .numQubits = 2})
      .Cases({"ccx", "cswap"}, Sig{.numParams = 0, .numQubits = 3})
      .Default(std::nullopt);
}

/// Returns the statement of the entry body that contains `op`, or null if there is none.
static Operation* getEntryStatement(Operation* op) {
  while ((op != nullptr) && !isEntryPoint(op->getParentOp())) {
    op = op->getParentOp();
  }
  return op;
}

LogicalResult GateCallOp::verify() {
  // Registers broadcast, so they must agree in size.
  std::optional<int64_t> broadcastSize;
  for (Value qubits : getQubits()) {
    const std::optional<int64_t> size = getRegisterSize(qubits.getType());
    if (!size || ShapedType::isDynamic(*size)) {
      continue;
    }
    if (broadcastSize && *broadcastSize != *size) {
      return emitOpError() << "registers of sizes " << *broadcastSize << " and " << *size
                           << " cannot be broadcast together";
    }
    broadcastSize = size;
  }
  return success();
}

/// Checks:
/// - The gate is known (builtin, standard, or from an include).
/// - The gate's signature is consistent with the definition of it, if any, else with the other calls.
LogicalResult GateCallOp::verifySymbolUses(SymbolTableCollection& symbolTable) {
  const StringRef name = getCallee();
  auto checkSignature = [&](GateSignature signature) -> LogicalResult {
    if (getParams().size() != signature.numParams || getQubits().size() != signature.numQubits) {
      return emitOpError() << "gate '" << name << "' takes " << signature.numParams << " parameter(s) and "
                           << signature.numQubits << " qubit(s), got " << getParams().size() << " and "
                           << getQubits().size();
    }
    return success();
  };

  if (Operation* symbol = symbolTable.lookupNearestSymbolFrom(*this, getCalleeAttr())) {
    InFlightDiagnostic diag = emitOpError() << "calls '@" << name << "', which is not a gate";
    diag.attachNote(symbol->getLoc()) << "'@" << name << "' is defined here";
    return diag;
  }

  if (const std::optional<GateSignature> signature = lookupBuiltinGate(name)) {
    return checkSignature(*signature);
  }

  // A standard gate or a gate from an unresolved include is only known after its include.
  Operation* statement = getEntryStatement(*this);
  auto entry = (statement != nullptr) ? dyn_cast<func::FuncOp>(statement->getParentOp()) : nullptr;
  const std::optional<GateSignature> standardSignature = lookupStandardGate(name);
  bool standardGatesIncluded = false;
  bool unresolvedIncluded = false;
  if (entry) {
    for (IncludeOp include : entry.getBody().getOps<IncludeOp>()) {
      if (!include->isBeforeInBlock(statement)) {
        break;
      }
      // TODO: An unresolved stdgates.inc also counts as an unresolved include here, so any unknown gate is accepted
      // (with a consistent signature), not just the standard ones. Tighten once includes are actually read.
      unresolvedIncluded |= include.getUnresolved();
      standardGatesIncluded |= include.getUnresolved() && include.getPath() == standardGatesInclude;
    }
  }
  if (standardSignature && standardGatesIncluded) {
    return checkSignature(*standardSignature);
  }
  if (unresolvedIncluded) {
    // The unknown gate's signature is checked for consistency across all of its calls by the program verifier.
    return success();
  }

  InFlightDiagnostic diag = emitOpError() << "calls the unknown gate '" << name << "'";
  if (standardSignature) {
    diag.attachNote() << "'" << name << "' is a standard gate; it needs an earlier 'include \"" << standardGatesInclude
                      << "\";'";
  }
  return diag;
}
