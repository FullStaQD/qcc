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

namespace {

class ProgramVerifier {
public:
  explicit ProgramVerifier(ModuleOp module) : module(module) {}

  LogicalResult verify() {
    if (failed(verifyEntryFunction())) {
      return failure();
    }
    collect();
    return failure(failed(verifyIncludes()) || failed(verifyMarkers()) || failed(verifyDefineBeforeUse()) ||
                   failed(verifyStandardGateCalls()));
  }

private:
  /// A use of the global definition `name` by `user`. The use is ordered by `anchor`: the statement of the entry body
  /// or the global definition that contains `user`.
  struct GlobalUse {
    StringRef name;
    Operation* user;
    Operation* anchor;
  };

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

  /// Collects what the checks need in a single walk of the module.
  void collect() {
    for (Operation& op : *module.getBody()) {
      if (&op == entry.getOperation()) {
        continue;
      }
      if (auto symbol = dyn_cast<SymbolOpInterface>(op)) {
        globals.try_emplace(symbol.getName(), &op);
      }
    }

    Block* entryBlock = &entry.getBody().front();
    const StringRef tagName = OQ3Dialect::FromIncludeAttrHelper::getNameStr();
    // The walk is pre-order, so the anchor is set before the ops it contains are visited.
    Operation* anchor = nullptr;
    bool standardGatesIncluded = false;
    module.walk<WalkOrder::PreOrder>([&](Operation* op) {
      if (op->getBlock() == entryBlock) {
        anchor = op;
      } else if (op->getParentOp() == module.getOperation()) {
        auto symbol = dyn_cast<SymbolOpInterface>(op);
        anchor = symbol && globals.lookup(symbol.getName()) == op ? op : nullptr;
      }

      if (auto include = dyn_cast<IncludeOp>(op)) {
        includeOps.push_back(include);
        if (op->getBlock() == entryBlock && include.getPath() == standardGatesInclude) {
          standardGatesIncluded = true;
        }
      }
      // Only statements of the entry body after the include see the standard gates.
      if (auto call = dyn_cast<GateCallOp>(op)) {
        const bool seesStandardGates = standardGatesIncluded && anchor != nullptr && anchor->getBlock() == entryBlock;
        const StringRef callee = call.getCallee();
        if (!seesStandardGates && !globals.contains(callee) && !lookupBuiltinGate(callee) &&
            lookupStandardGate(callee)) {
          standardGateCallsBeforeInclude.push_back(call);
        }
      }
      if (op->getAttrOfType<IntegerAttr>(tagName) != nullptr) {
        taggedOps.push_back(op);
      }
      if (auto marker = dyn_cast<DefinedOp>(op)) {
        if (op->getBlock() == entryBlock) {
          markerOps.push_back(marker);
        }
        return;
      }
      if (anchor == nullptr) {
        return;
      }
      op->getAttrDictionary().walk([&](SymbolRefAttr ref) {
        auto it = globals.find(ref.getRootReference().getValue());
        if (it != globals.end()) {
          uses.push_back({.name = it->first(), .user = op, .anchor = anchor});
        }
      });
    });
  }

  LogicalResult verifyIncludes() {
    for (IncludeOp include : includeOps) {
      auto [it, inserted] = includes.try_emplace(include.getIdAttr().getInt(), include);
      if (!inserted) {
        InFlightDiagnostic diag = include.emitOpError() << "has the id " << include.getId() << " of another include";
        diag.attachNote(it->second.getLoc()) << "the other include is here";
        return diag;
      }
    }

    // Every tag names an include.
    const StringRef tagName = OQ3Dialect::FromIncludeAttrHelper::getNameStr();
    for (Operation* op : taggedOps) {
      const int64_t id = op->getAttrOfType<IntegerAttr>(tagName).getInt();
      if (!includes.contains(id)) {
        return op->emitOpError() << "is tagged '" << tagName << " = " << id << "', but no include has that id";
      }
    }
    return success();
  }

  LogicalResult verifyMarkers() {
    for (DefinedOp marker : markerOps) {
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

  /// A statement may use what is defined before it. A definition may use what is defined before it, and itself.
  /// Only the position of the statement or definition that contains the use matters.
  LogicalResult verifyDefineBeforeUse() {
    for (const GlobalUse& use : uses) {
      Operation* position = use.anchor;
      if (auto symbol = dyn_cast<SymbolOpInterface>(use.anchor)) {
        if (symbol.getName() == use.name) {
          continue;
        }
        position = markers.lookup(symbol.getName());
      }
      DefinedOp marker = markers.lookup(use.name);
      if (!marker->isBeforeInBlock(position)) {
        InFlightDiagnostic diag = use.user->emitOpError() << "uses '@" << use.name << "' before its definition";
        diag.attachNote(marker.getLoc()) << "it is defined here";
        return diag;
      }
    }
    return success();
  }

  LogicalResult verifyStandardGateCalls() {
    if (standardGateCallsBeforeInclude.empty()) {
      return success();
    }
    GateCallOp call = standardGateCallsBeforeInclude.front();
    InFlightDiagnostic diag = call.emitOpError() << "calls the unknown gate '" << call.getCallee() << "'";
    diag.attachNote() << "'" << call.getCallee() << "' is a standard gate; it needs an earlier 'include \""
                      << standardGatesInclude << "\";'";
    return diag;
  }

  ModuleOp module;
  func::FuncOp entry;
  /// The global definitions of the program: all symbols of the module but the entry function.
  llvm::StringMap<Operation*> globals;
  SmallVector<IncludeOp> includeOps;
  SmallVector<Operation*> taggedOps;
  SmallVector<DefinedOp> markerOps;
  SmallVector<GlobalUse> uses;
  SmallVector<GateCallOp> standardGateCallsBeforeInclude;
  llvm::DenseMap<int64_t, IncludeOp> includes;
  llvm::StringMap<DefinedOp> markers;
};

} // namespace

/// For our purposes, a statement is an op in a function body.
/// TODO: Don't forget gate bodies here.
static bool isStatement(Operation* op) { return isa_and_present<func::FuncOp>(op->getParentOp()); }

LogicalResult OQ3Dialect::verifyOperationAttribute(Operation* op, NamedAttribute attr) {
  const StringRef name = attr.getName().getValue();

  // OpenQASM version
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

  // Include tag
  if (name == FromIncludeAttrHelper::getNameStr()) {
    if (!isa<IntegerAttr>(attr.getValue())) {
      return op->emitOpError() << "attribute '" << name << "' must be an include id, got " << attr.getValue();
    }
    return success();
  }

  // Annotations
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

  return op->emitOpError() << "has the unknown attribute '" << name << "'";
}

//===----------------------------------------------------------------------===//
// Types
//===----------------------------------------------------------------------===//

static LogicalResult verifySize(function_ref<InFlightDiagnostic()> emitError, int64_t size) {
  if (size < 0) {
    return emitError() << "size must be non-negative, got " << size;
  }
  return success();
}

LogicalResult QRegType::verify(function_ref<InFlightDiagnostic()> emitError, int64_t size) {
  return verifySize(emitError, size);
}

LogicalResult BitsType::verify(function_ref<InFlightDiagnostic()> emitError, int64_t size) {
  return verifySize(emitError, size);
}

//===----------------------------------------------------------------------===//
// Attributes
//===----------------------------------------------------------------------===//

LogicalResult VersionAttr::verify(function_ref<InFlightDiagnostic()> emitError, unsigned major, unsigned minor) {
  if (major != 3 || minor > 2) {
    return emitError() << "unsupported OpenQASM version " << major << "." << minor
                       << ", supported are 3.0, 3.1, and 3.2";
    // TODO: By 3.2, we mean the current live version, which has improvements over 3.1.
    // Hopefully there will be a release soon so that we can eliminate the inaccuracy.
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

// The signature is generated, so the parameter cannot be taken by reference.
// NOLINTNEXTLINE(performance-unnecessary-value-param)
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
