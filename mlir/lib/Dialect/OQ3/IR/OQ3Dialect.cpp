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
#include "mlir/IR/Block.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Visitors.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/TypeSwitch.h" // IWYU pragma: keep

#include <optional>

using namespace mlir;
using namespace qcc;
using namespace qcc::oq3;

#include "qcc/Dialect/OQ3/IR/OQ3Dialect.cpp.inc"
#include "qcc/Dialect/OQ3/IR/OQ3Enums.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "qcc/Dialect/OQ3/IR/OQ3Types.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/OQ3/IR/OQ3Attrs.cpp.inc"

//===----------------------------------------------------------------------===//
// Dialect
//===----------------------------------------------------------------------===//

void OQ3Dialect::initialize() {
  registerTypes();
  registerAttributes();
  addOperations<
#define GET_OP_LIST
#include "qcc/Dialect/OQ3/IR/OQ3Ops.cpp.inc"
      >();
}

void OQ3Dialect::registerTypes() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "qcc/Dialect/OQ3/IR/OQ3Types.cpp.inc"
      >();
}

void OQ3Dialect::registerAttributes() {
  addAttributes<
#define GET_ATTRDEF_LIST
#include "qcc/Dialect/OQ3/IR/OQ3Attrs.cpp.inc"
      >();
}

//===----------------------------------------------------------------------===//
// Program structure
//===----------------------------------------------------------------------===//

bool qcc::oq3::isUnknownOrHasUnknownSize(Type type) {
  return TypeSwitch<Type, bool>(type)
      .Case([](UnknownType) { return true; })
      .Case([](QRegType reg) { return reg.hasUnknownSize(); })
      .Case([](BitsType bits) { return bits.hasUnknownSize(); })
      .Case([](RefType ref) { return isUnknownOrHasUnknownSize(ref.getElementType()); })
      .Default(false);
}

bool qcc::oq3::isValidCommentText(StringRef text) {
  if (text.starts_with("//")) {
    return !text.contains('\n') && !text.contains('\r');
  }
  // A block comment ends at its first `*/`.
  return text.size() >= 4 && text.starts_with("/*") && text.find("*/", 2) == text.size() - 2;
}

bool qcc::oq3::isValidTrailingCommentText(StringRef text) {
  if (text.empty()) {
    return false;
  }
  while (!text.empty()) {
    if (text.starts_with("//")) {
      return isValidCommentText(text);
    }
    const size_t end = text.find("*/", 2);
    if (!text.starts_with("/*") || end == StringRef::npos) {
      return false;
    }
    // Only a line break inside a block comment keeps the comments on the line of the statement.
    text = text.drop_front(end + 2);
    const StringRef separator = text.take_while([](char c) { return c == ' ' || c == '\t'; });
    text = text.drop_front(separator.size());
  }
  return true;
}

namespace {

/// Checks an OpenQASM program as a whole: what no single operation can check by itself.
class ProgramVerifier {
public:
  explicit ProgramVerifier(ModuleOp module) : module(module) {}

  LogicalResult verify() {
    if (failed(verifyEntryFunction()) || failed(verifyIncludes()) || failed(verifyMarkers()) ||
        failed(verifyDefineBeforeUse())) {
      return failure();
    }
    return hasUnresolved ? verifyUnresolvedConsistency() : verifyNothingUnresolved();
  }

private:
  LogicalResult verifyEntryFunction() {
    SmallVector<FunctionOpInterface> entryPoints = getEntryPoints(module);
    if (entryPoints.empty()) {
      return module.emitOpError() << "is an OpenQASM program ('" << OQ3Dialect::VersionAttrHelper::getNameStr()
                                  << "'), so it needs an entry function ('"
                                  << QccDialect::EntryPointAttrHelper::getNameStr() << "')";
    }
    if (entryPoints.size() > 1) {
      InFlightDiagnostic diag = entryPoints[1].emitOpError()
                                << "is a second entry function, but a program has exactly one";
      diag.attachNote(entryPoints[0].getLoc()) << "the first entry function is here";
      return diag;
    }
    entry = dyn_cast<func::FuncOp>(entryPoints[0].getOperation());
    if (!entry) {
      return entryPoints[0].emitOpError()
             << "is the entry function of an OpenQASM program, so it must be a 'func.func'";
    }
    if (entry.isExternal() || !entry.getBody().hasOneBlock()) {
      return entry.emitOpError() << "is the entry function of an OpenQASM program, so it needs a body of one block";
    }
    if (entry.getNumArguments() != 0 || entry.getNumResults() != 0) {
      return entry.emitOpError()
             << "is the entry function of an OpenQASM program, so it takes no arguments and returns no results";
    }
    return success();
  }

  LogicalResult verifyIncludes() {
    WalkResult result = module.walk([&](IncludeOp include) {
      auto [it, inserted] = includes.try_emplace(include.getId(), include);
      if (!inserted) {
        InFlightDiagnostic diag = include.emitOpError() << "has the id " << include.getId() << " of another include";
        diag.attachNote(it->second.getLoc()) << "the other include is here";
        return WalkResult::interrupt();
      }
      hasUnresolved |= include.getUnresolved();
      return WalkResult::advance();
    });
    if (result.wasInterrupted()) {
      return failure();
    }

    // Every tag names an include.
    const StringRef tagName = OQ3Dialect::FromIncludeAttrHelper::getNameStr();
    result = module.walk([&](Operation* op) {
      auto tag = op->getAttrOfType<IntegerAttr>(tagName);
      if (tag && !includes.contains(tag.getInt())) {
        op->emitOpError() << "is tagged '" << tagName << " = " << tag.getInt() << "', but no include has that id";
        return WalkResult::interrupt();
      }
      return WalkResult::advance();
    });
    return failure(result.wasInterrupted());
  }

  LogicalResult verifyMarkers() {
    for (Operation& op : *module.getBody()) {
      if (&op == entry.getOperation()) {
        continue;
      }
      if (auto symbol = dyn_cast<SymbolOpInterface>(op)) {
        globals.try_emplace(symbol.getName(), &op);
      }
    }

    for (auto marker : entry.getBody().getOps<DefinedOp>()) {
      const StringRef name = marker.getSymbol();
      if (!globals.contains(name)) {
        return marker.emitOpError() << "marks '@" << name << "', which is no global definition of the module";
      }
      auto [it, inserted] = markers.try_emplace(name, marker);
      if (!inserted) {
        InFlightDiagnostic diag = marker.emitOpError() << "marks '@" << name << "' a second time";
        diag.attachNote(it->second.getLoc()) << "the first marker is here";
        return diag;
      }
    }

    for (auto& [name, op] : globals) {
      if (!markers.contains(name)) {
        return op->emitOpError() << "is a global definition, but the entry body has no 'oq3.defined @" << name
                                 << "' marker for its position";
      }
    }
    return success();
  }

  /// Calls `callback` for every global symbol that an attribute of `op` refers to.
  void forEachGlobalUse(Operation* op, llvm::function_ref<void(StringRef, Operation*)> callback) {
    if (isa<DefinedOp>(op)) {
      return;
    }
    op->getAttrDictionary().walk([&](SymbolRefAttr ref) {
      auto it = globals.find(ref.getRootReference().getValue());
      if (it != globals.end()) {
        callback(it->first(), it->second);
      }
    });
  }

  LogicalResult verifyDefineBeforeUse() {
    LogicalResult result = success();
    // A statement may use what is defined before it.
    for (Operation& statement : entry.getBody().front()) {
      statement.walk([&](Operation* user) {
        forEachGlobalUse(user, [&](StringRef name, Operation*) {
          DefinedOp marker = markers.lookup(name);
          if (succeeded(result) && !marker->isBeforeInBlock(&statement)) {
            InFlightDiagnostic diag = user->emitOpError() << "uses '@" << name << "' before its definition";
            diag.attachNote(marker.getLoc()) << "it is defined here";
            result = failure();
          }
        });
      });
    }

    // A definition may use what is defined before it, and itself.
    for (auto& [definitionName, definition] : globals) {
      DefinedOp definitionMarker = markers.lookup(definitionName);
      definition->walk([&](Operation* user) {
        forEachGlobalUse(user, [&](StringRef name, Operation*) {
          DefinedOp marker = markers.lookup(name);
          if (succeeded(result) && name != definitionName && !marker->isBeforeInBlock(definitionMarker)) {
            InFlightDiagnostic diag = user->emitOpError() << "uses '@" << name << "' before its definition";
            diag.attachNote(marker.getLoc()) << "it is defined here";
            result = failure();
          }
        });
      });
    }
    return result;
  }

  /// Without an unresolved include, nothing may depend on an unknown name.
  LogicalResult verifyNothingUnresolved() {
    WalkResult result = module.walk([&](Operation* op) {
      if (isa<UnresolvedOp, UnresolvedCallOp>(op)) {
        op->emitOpError() << "is only valid in a program with an unresolved include";
        return WalkResult::interrupt();
      }
      for (Value result : op->getResults()) {
        if (isUnknownOrHasUnknownSize(result.getType())) {
          op->emitOpError() << "has a result of type " << result.getType()
                            << ", which is only valid in a program with an unresolved include";
          return WalkResult::interrupt();
        }
      }
      return WalkResult::advance();
    });
    return failure(result.wasInterrupted());
  }

  /// All calls of the same unknown gate or subroutine agree on its signature.
  LogicalResult verifyUnresolvedConsistency() {
    const bool hasStandardGates = llvm::any_of(entry.getBody().getOps<IncludeOp>(), [](IncludeOp include) {
      return include.getPath() == standardGatesInclude && !include.getUnresolved();
    });

    llvm::StringMap<GateCallOp> gateCalls;
    llvm::StringMap<UnresolvedCallOp> subroutineCalls;
    WalkResult result = module.walk([&](Operation* op) {
      if (auto call = dyn_cast<GateCallOp>(op)) {
        const StringRef name = call.getCallee();
        if (globals.contains(name) || lookupBuiltinGate(name) || (hasStandardGates && lookupStandardGate(name))) {
          return WalkResult::advance();
        }
        auto [it, inserted] = gateCalls.try_emplace(name, call);
        GateCallOp first = it->second;
        if (!inserted && (first.getParams().size() != call.getParams().size() ||
                          first.getQubits().size() != call.getQubits().size())) {
          InFlightDiagnostic diag = call.emitOpError()
                                    << "calls the unknown gate '@" << name << "' with " << call.getParams().size()
                                    << " parameter(s) and " << call.getQubits().size() << " qubit(s), but another call "
                                    << "uses " << first.getParams().size() << " and " << first.getQubits().size();
          diag.attachNote(first.getLoc()) << "the other call is here";
          return WalkResult::interrupt();
        }
      } else if (auto call = dyn_cast<UnresolvedCallOp>(op)) {
        auto [it, inserted] = subroutineCalls.try_emplace(call.getCallee(), call);
        UnresolvedCallOp first = it->second;
        if (!inserted && first.getArgs().size() != call.getArgs().size()) {
          InFlightDiagnostic diag = call.emitOpError()
                                    << "calls '" << call.getCallee() << "' with " << call.getArgs().size()
                                    << " argument(s), but another call uses " << first.getArgs().size();
          diag.attachNote(first.getLoc()) << "the other call is here";
          return WalkResult::interrupt();
        }
      }
      return WalkResult::advance();
    });
    return failure(result.wasInterrupted());
  }

  ModuleOp module;
  func::FuncOp entry;
  bool hasUnresolved = false;
  llvm::DenseMap<int64_t, IncludeOp> includes;
  /// The global definitions of the program: all symbols of the module but the entry function.
  llvm::StringMap<Operation*> globals;
  llvm::StringMap<DefinedOp> markers;
};

} // namespace

/// Whether `op` is a statement: an operation directly in a list of statements.
static bool isStatement(Operation* op) { return isa_and_present<func::FuncOp>(op->getParentOp()); }

LogicalResult OQ3Dialect::verifyOperationAttribute(Operation* op, NamedAttribute attr) {
  const StringRef name = attr.getName().getValue();

  if (name == VersionAttrHelper::getNameStr()) {
    auto module = dyn_cast<ModuleOp>(op);
    if (!module) {
      return op->emitOpError() << "attribute '" << name << "' is only valid on a module";
    }
    if (!isa<VersionAttr>(attr.getValue())) {
      return op->emitOpError() << "attribute '" << name << "' must be an '#oq3.version', got " << attr.getValue();
    }
    return ProgramVerifier(module).verify();
  }

  if (name == FromIncludeAttrHelper::getNameStr()) {
    if (!isa<IntegerAttr>(attr.getValue())) {
      return op->emitOpError() << "attribute '" << name << "' must be an include id, got " << attr.getValue();
    }
    return success();
  }

  if (name == TrailingCommentAttrHelper::getNameStr()) {
    auto text = dyn_cast<StringAttr>(attr.getValue());
    if (!text || !isValidTrailingCommentText(text.getValue())) {
      return op->emitOpError() << "attribute '" << name << "' must be the text of comments on one line, got "
                               << attr.getValue();
    }
    if (!isStatement(op)) {
      return op->emitOpError() << "attribute '" << name << "' is only valid on a statement";
    }
    return success();
  }

  if (name == AnnotationsAttrHelper::getNameStr()) {
    auto annotations = dyn_cast<ArrayAttr>(attr.getValue());
    if (!annotations || !llvm::all_of(annotations, llvm::IsaPred<AnnotationAttr>)) {
      return op->emitOpError() << "attribute '" << name << "' must be an array of '#oq3.annotation', got "
                               << attr.getValue();
    }
    if (!isStatement(op)) {
      return op->emitOpError() << "attribute '" << name << "' is only valid on a statement";
    }
    return success();
  }

  if (name == ArrowAttrHelper::getNameStr()) {
    if (!isa<UnitAttr>(attr.getValue())) {
      return op->emitOpError() << "attribute '" << name << "' must be a unit attribute, got " << attr.getValue();
    }
    auto store = dyn_cast<RefStoreOp>(op);
    if (!store || !store.getValue().getDefiningOp<MeasureOp>()) {
      return op->emitOpError() << "attribute '" << name << "' is only valid on a 'qcc.ref.store' of a measurement";
    }
    return success();
  }

  return op->emitOpError() << "has the unknown attribute '" << name << "'";
}

//===----------------------------------------------------------------------===//
// Types
//===----------------------------------------------------------------------===//

/// Parses `<n>` or `<?>`.
static FailureOr<int64_t> parseSize(AsmParser& parser) {
  int64_t size = ShapedType::kDynamic;
  if (parser.parseLess()) {
    return failure();
  }
  if (failed(parser.parseOptionalQuestion()) && parser.parseInteger(size)) {
    return failure();
  }
  if (parser.parseGreater()) {
    return failure();
  }
  return size;
}

/// Prints `<n>` or `<?>`.
static void printSize(AsmPrinter& printer, int64_t size) {
  printer << "<";
  if (ShapedType::isDynamic(size)) {
    printer << "?";
  } else {
    printer << size;
  }
  printer << ">";
}

static LogicalResult verifySize(function_ref<InFlightDiagnostic()> emitError, int64_t size) {
  if (size < 0 && !ShapedType::isDynamic(size)) {
    return emitError() << "size must be non-negative or '?', got " << size;
  }
  return success();
}

Type QRegType::parse(AsmParser& parser) {
  FailureOr<int64_t> size = parseSize(parser);
  if (failed(size)) {
    return {};
  }
  return getChecked([&] { return parser.emitError(parser.getNameLoc()); }, parser.getContext(), *size);
}

void QRegType::print(AsmPrinter& printer) const { printSize(printer, getSize()); }

LogicalResult QRegType::verify(function_ref<InFlightDiagnostic()> emitError, int64_t size) {
  return verifySize(emitError, size);
}

Type BitsType::parse(AsmParser& parser) {
  FailureOr<int64_t> size = parseSize(parser);
  if (failed(size)) {
    return {};
  }
  return getChecked([&] { return parser.emitError(parser.getNameLoc()); }, parser.getContext(), *size);
}

void BitsType::print(AsmPrinter& printer) const { printSize(printer, getSize()); }

LogicalResult BitsType::verify(function_ref<InFlightDiagnostic()> emitError, int64_t size) {
  return verifySize(emitError, size);
}

//===----------------------------------------------------------------------===//
// Attributes
//===----------------------------------------------------------------------===//

Attribute VersionAttr::parse(AsmParser& parser, Type /*type*/) {
  unsigned major = 0;
  std::optional<unsigned> minor;
  bool implicit = false;
  if (parser.parseLess() || parser.parseInteger(major)) {
    return {};
  }
  while (succeeded(parser.parseOptionalComma())) {
    if (succeeded(parser.parseOptionalKeyword("implicit"))) {
      implicit = true;
      break;
    }
    if (minor) {
      parser.emitError(parser.getCurrentLocation()) << "expected 'implicit'";
      return {};
    }
    unsigned value = 0;
    if (parser.parseInteger(value)) {
      return {};
    }
    minor = value;
  }
  if (parser.parseGreater()) {
    return {};
  }
  return getChecked([&] { return parser.emitError(parser.getNameLoc()); }, parser.getContext(), major, minor, implicit);
}

void VersionAttr::print(AsmPrinter& printer) const {
  printer << "<" << getMajor();
  if (getMinor()) {
    printer << ", " << *getMinor();
  }
  if (getImplicit()) {
    printer << ", implicit";
  }
  printer << ">";
}

LogicalResult VersionAttr::verify(function_ref<InFlightDiagnostic()> emitError, unsigned major,
                                  std::optional<unsigned> minor, bool /*implicit*/) {
  if (major != 3 || minor.value_or(0) > 2) {
    return emitError() << "unsupported OpenQASM version " << major << "." << minor.value_or(0)
                       << ", supported are 3.0, 3.1, and 3.2";
  }
  return success();
}

LogicalResult AnnotationAttr::verify(function_ref<InFlightDiagnostic()> emitError, StringRef name, StringRef content) {
  if (name.empty() || name.starts_with("@") || name.find_first_of(" \t\r\n") != StringRef::npos) {
    return emitError() << "annotation keyword must be a dotted identifier without '@', got '" << name << "'";
  }
  if (content.find_first_of("\r\n") != StringRef::npos) {
    return emitError() << "annotation content must be a single line";
  }
  return success();
}

Attribute IntLiteralAttr::parse(AsmParser& parser, Type type) {
  APInt value;
  if (parser.parseLess()) {
    return {};
  }
  const SMLoc loc = parser.getCurrentLocation();
  OptionalParseResult result = parser.parseOptionalInteger(value);
  if (!result.has_value() || failed(*result)) {
    parser.emitError(loc) << "expected an integer";
    return {};
  }
  if (value.isNegative()) {
    parser.emitError(loc) << "an integer literal is non-negative";
    return {};
  }
  if (parser.parseGreater()) {
    return {};
  }
  if (!type) {
    parser.emitError(loc) << "expected the type of the integer literal, as in '#oq3.int<1> : !oq3.int'";
    return {};
  }
  const unsigned width = std::max(1U, value.getActiveBits());
  return getChecked([&] { return parser.emitError(loc); }, parser.getContext(), value.zextOrTrunc(width), type);
}

void IntLiteralAttr::print(AsmPrinter& printer) const {
  printer << "<" << llvm::toString(getValue(), 10, /*Signed=*/false) << ">";
}

LogicalResult IntLiteralAttr::verify(function_ref<InFlightDiagnostic()> emitError, APInt /*value*/, Type type) {
  if (!isa<UnsizedIntType>(type)) {
    return emitError() << "an integer literal has type '!oq3.int', got " << type;
  }
  return success();
}

LogicalResult FloatLiteralAttr::verify(function_ref<InFlightDiagnostic()> emitError, StringRef text, Type type) {
  const bool wellFormed = llvm::any_of(text, llvm::isDigit) && llvm::all_of(text, [](char c) {
                            return llvm::isDigit(c) || c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-';
                          });
  if (!wellFormed) {
    return emitError() << "expected the text of a floating-point literal, got '" << text << "'";
  }
  if (!isa<UnsizedFloatType>(type)) {
    return emitError() << "a floating-point literal has type '!oq3.float', got " << type;
  }
  return success();
}

LogicalResult BitstringAttr::verify(function_ref<InFlightDiagnostic()> emitError, StringRef bits, Type type) {
  if (bits.empty() || !llvm::all_of(bits, [](char c) { return c == '0' || c == '1'; })) {
    return emitError() << "a bitstring is a non-empty string of '0' and '1', got '" << bits << "'";
  }
  auto bitsType = dyn_cast<BitsType>(type);
  if (!bitsType || bitsType.getSize() != static_cast<int64_t>(bits.size())) {
    return emitError() << "a bitstring of " << bits.size() << " bit(s) has type '!oq3.bits<" << bits.size()
                       << ">', got " << type;
  }
  return success();
}
