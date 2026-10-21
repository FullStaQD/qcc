// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/OQ3/Export/Export.h"

#include "qcc/Dialect/OQ3/IR/OQ3.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Tools/mlir-translate/Translation.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/raw_ostream.h"

#include <cstdint>
#include <string>

using namespace mlir;
using namespace qcc;
using namespace qcc::oq3;

namespace {

/// Binding strength of a printed expression, see the precedence table of the spec. Higher binds tighter.
enum class Precedence : uint8_t {
  Additive = 1,
  Multiplicative = 2,
  Unary = 3,
  Atom = 4,
};

/// A printed expression.
struct Printed {
  std::string text;
  Precedence precedence = Precedence::Atom;
};

class Exporter {
public:
  explicit Exporter(llvm::raw_ostream& os) : os(os) {}

  LogicalResult run(Operation* op);

private:
  LogicalResult printStatement(Operation* op);
  FailureOr<std::string> printStatementBody(Operation* op);
  FailureOr<Printed> printExpr(Value value);
  FailureOr<std::string> printList(ValueRange values);
  FailureOr<std::string> printDesignator(Value designator, int64_t size);

  // NOLINTNEXTLINE(cppcoreguidelines-avoid-const-or-ref-data-members): non-owning, outlived by the stream.
  llvm::raw_ostream& os;
};

} // namespace

/// Whether `op` is printed as a statement of its own, rather than as part of the statements that use its result.
static bool isStatement(Operation* op) {
  if (isa<MeasureOp>(op)) {
    return op->use_empty();
  }
  return isa<PragmaOp, IncludeOp, DefinedOp, QubitDeclOp, DeclareOp, GateCallOp, ResetOp, BarrierOp, RefStoreOp>(op);
}

/// Whether `op` computes a value that its users print.
static bool isExpression(Operation* op) {
  return isa<ConstantOp, MathConstantOp, UnaryOp, BinaryOp, CastOp, RefLoadOp, SubrefOp, QubitIndexOp, PhysicalQubitOp,
             MeasureOp>(op);
}

/// Prints `path` in quotes. A path can contain one kind of quote, so the other one delimits it.
static std::string quotePath(StringRef path) {
  const char quote = path.contains('"') ? '\'' : '"';
  return (Twine(quote) + path + Twine(quote)).str();
}

static std::string printMathConstant(MathConstantOp constant) {
  switch (constant.getKind()) {
  case MathConstantKind::Pi:
    return "pi";
  case MathConstantKind::Tau:
    return "tau";
  case MathConstantKind::Euler:
    return "euler";
  }
  llvm_unreachable("unknown math constant");
}

static FailureOr<std::string> printLiteral(ConstantOp constant) {
  if (auto literal = dyn_cast<IntLiteralAttr>(constant.getValue())) {
    return llvm::toString(literal.getValue(), 10, /*Signed=*/false);
  }
  if (auto literal = dyn_cast<FloatLiteralAttr>(constant.getValue())) {
    return literal.getText().str();
  }
  if (auto literal = dyn_cast<BitstringAttr>(constant.getValue())) {
    return "\"" + literal.getText() + "\"";
  }
  return constant.emitOpError() << "cannot be exported to OpenQASM";
}

/// The OpenQASM spelling of a type an explicit cast converts to.
static FailureOr<std::string> printCastType(CastOp cast) {
  return TypeSwitch<Type, FailureOr<std::string>>(cast.getType())
      .Case([](UnsizedFloatType) { return std::string("float"); })
      .Case([](AngleType) { return std::string("angle"); })
      .Case([](BitType) { return std::string("bit"); })
      .Default([&](Type type) -> FailureOr<std::string> {
        return cast.emitOpError() << "cannot export a cast to " << type << " to OpenQASM";
      });
}

LogicalResult Exporter::run(Operation* op) {
  auto module = dyn_cast<ModuleOp>(op);
  auto version = module ? module->getAttrOfType<VersionAttr>(OQ3Dialect::VersionAttrHelper::getNameStr()) : nullptr;
  if (!version) {
    return op->emitError() << "is not an OpenQASM program: expected a module with the '"
                           << OQ3Dialect::VersionAttrHelper::getNameStr() << "' attribute";
  }
  SmallVector<FunctionOpInterface> entryPoints = getEntryPoints(module);
  auto entry = entryPoints.size() == 1 ? dyn_cast<func::FuncOp>(entryPoints[0].getOperation()) : nullptr;
  if (!entry || entry.isExternal()) {
    return module.emitError("the OpenQASM program has no entry function");
  }
  Block& body = entry.getBody().front();

  os << "OPENQASM " << version.getMajor() << "." << version.getMinor() << ";\n";

  const StringRef tagName = OQ3Dialect::FromIncludeAttrHelper::getNameStr();
  for (Operation& statement : body) {
    if (statement.hasAttr(tagName) || &statement == body.getTerminator()) {
      continue;
    }
    if (isStatement(&statement)) {
      if (failed(printStatement(&statement))) {
        return failure();
      }
      continue;
    }
    if (!isExpression(&statement)) {
      return statement.emitOpError() << "cannot be exported to OpenQASM";
    }
  }
  return success();
}

LogicalResult Exporter::printStatement(Operation* op) {
  FailureOr<std::string> text = printStatementBody(op);
  if (failed(text)) {
    return failure();
  }
  if (auto annotations = op->getAttrOfType<ArrayAttr>(OQ3Dialect::AnnotationsAttrHelper::getNameStr())) {
    for (auto annotation : annotations.getAsRange<AnnotationAttr>()) {
      os << "@" << annotation.getName();
      if (!annotation.getContent().empty()) {
        os << " " << annotation.getContent();
      }
      os << "\n";
    }
  }
  os << *text << "\n";
  return success();
}

FailureOr<std::string> Exporter::printDesignator(Value designator, int64_t size) {
  if (!designator) {
    return "[" + std::to_string(size) + "]";
  }
  FailureOr<Printed> printed = printExpr(designator);
  if (failed(printed)) {
    return failure();
  }
  return "[" + printed->text + "]";
}

FailureOr<std::string> Exporter::printList(ValueRange values) {
  SmallVector<std::string> parts;
  for (Value value : values) {
    FailureOr<Printed> printed = printExpr(value);
    if (failed(printed)) {
      return failure();
    }
    parts.push_back(std::move(printed->text));
  }
  return llvm::join(parts, ", ");
}

FailureOr<std::string> Exporter::printStatementBody(Operation* op) {
  return TypeSwitch<Operation*, FailureOr<std::string>>(op)
      .Case([](PragmaOp pragma) { return ("pragma " + pragma.getText()).str(); })
      .Case([](IncludeOp include) { return "include " + quotePath(include.getPath()) + ";"; })
      .Case([](DefinedOp marker) -> FailureOr<std::string> {
        return marker.emitOpError() << "marks a global definition, whose export is not supported yet";
      })
      .Case([&](QubitDeclOp decl) -> FailureOr<std::string> {
        const StringRef name = decl.getName();
        auto reg = dyn_cast<QRegType>(decl.getType());
        std::string designator;
        if (reg) {
          FailureOr<std::string> printed = printDesignator(decl.getDesignator(), reg.getSize());
          if (failed(printed)) {
            return failure();
          }
          designator = *printed;
        }
        return ("qubit" + designator + " " + name + ";").str();
      })
      .Case([&](DeclareOp decl) -> FailureOr<std::string> {
        const StringRef name = decl.getName();
        auto bits = dyn_cast<BitsType>(decl.getType().getElementType());
        std::string designator;
        if (bits) {
          FailureOr<std::string> printed = printDesignator(decl.getDesignator(), bits.getSize());
          if (failed(printed)) {
            return failure();
          }
          designator = *printed;
        }
        std::string text = ("bit" + designator + " " + name).str();
        if (decl.getInit()) {
          FailureOr<Printed> init = printExpr(decl.getInit());
          if (failed(init)) {
            return failure();
          }
          text += " = " + init->text;
        }
        return text + ";";
      })
      .Case([&](GateCallOp call) -> FailureOr<std::string> {
        std::string text = call.getCallee().str();
        if (!call.getParams().empty()) {
          FailureOr<std::string> params = printList(call.getParams());
          if (failed(params)) {
            return failure();
          }
          text += "(" + *params + ")";
        }
        if (!call.getQubits().empty()) {
          FailureOr<std::string> qubits = printList(call.getQubits());
          if (failed(qubits)) {
            return failure();
          }
          text += " " + *qubits;
        }
        return text + ";";
      })
      .Case([&](ResetOp reset) -> FailureOr<std::string> {
        FailureOr<Printed> qubits = printExpr(reset.getQubits());
        if (failed(qubits)) {
          return failure();
        }
        return "reset " + qubits->text + ";";
      })
      .Case([&](BarrierOp barrier) -> FailureOr<std::string> {
        if (barrier.getQubits().empty()) {
          return std::string("barrier;");
        }
        FailureOr<std::string> qubits = printList(barrier.getQubits());
        if (failed(qubits)) {
          return failure();
        }
        return "barrier " + *qubits + ";";
      })
      .Case([&](RefStoreOp store) -> FailureOr<std::string> {
        FailureOr<Printed> target = printExpr(store.getRef());
        FailureOr<Printed> value = printExpr(store.getValue());
        if (failed(target) || failed(value)) {
          return failure();
        }
        return target->text + " = " + value->text + ";";
      })
      .Case([&](MeasureOp measure) -> FailureOr<std::string> {
        FailureOr<Printed> printed = printExpr(measure.getResult());
        if (failed(printed)) {
          return failure();
        }
        return printed->text + ";";
      })
      .Default([](Operation* other) -> FailureOr<std::string> {
        return other->emitOpError() << "cannot be exported to OpenQASM";
      });
}

FailureOr<Printed> Exporter::printExpr(Value value) {
  Operation* op = value.getDefiningOp();
  if (op == nullptr) {
    return emitError(value.getLoc()) << "cannot export a block argument to OpenQASM";
  }
  auto atom = [](std::string text) -> FailureOr<Printed> { return Printed{.text = std::move(text)}; };

  return TypeSwitch<Operation*, FailureOr<Printed>>(op)
      .Case([&](ConstantOp constant) -> FailureOr<Printed> {
        FailureOr<std::string> text = printLiteral(constant);
        if (failed(text)) {
          return failure();
        }
        return atom(*text);
      })
      .Case([&](MathConstantOp constant) { return atom(printMathConstant(constant)); })
      .Case([&](UnaryOp unary) -> FailureOr<Printed> {
        FailureOr<Printed> operand = printExpr(unary.getOperand());
        if (failed(operand)) {
          return failure();
        }
        const std::string text = operand->precedence < Precedence::Unary ? "(" + operand->text + ")" : operand->text;
        return Printed{.text = "-" + text, .precedence = Precedence::Unary};
      })
      .Case([&](BinaryOp binary) -> FailureOr<Printed> {
        FailureOr<Printed> lhs = printExpr(binary.getLhs());
        FailureOr<Printed> rhs = printExpr(binary.getRhs());
        if (failed(lhs) || failed(rhs)) {
          return failure();
        }
        Precedence precedence = Precedence::Additive;
        StringRef symbol;
        switch (binary.getKind()) {
        case BinaryKind::Add:
          symbol = "+";
          break;
        case BinaryKind::Sub:
          symbol = "-";
          break;
        case BinaryKind::Mul:
          symbol = "*";
          precedence = Precedence::Multiplicative;
          break;
        case BinaryKind::Div:
          symbol = "/";
          precedence = Precedence::Multiplicative;
          break;
        }
        // The operators are left-associative, so a right operand of the same precedence needs parentheses.
        const std::string left = lhs->precedence < precedence ? "(" + lhs->text + ")" : lhs->text;
        const std::string right = rhs->precedence <= precedence ? "(" + rhs->text + ")" : rhs->text;
        return Printed{.text = left + " " + symbol.str() + " " + right, .precedence = precedence};
      })
      .Case([&](CastOp cast) -> FailureOr<Printed> {
        FailureOr<Printed> input = printExpr(cast.getInput());
        if (failed(input) || cast.getImplicit()) {
          return input;
        }
        FailureOr<std::string> type = printCastType(cast);
        if (failed(type)) {
          return failure();
        }
        return atom(*type + "(" + input->text + ")");
      })
      .Case([&](RefLoadOp load) { return printExpr(load.getRef()); })
      .Case([&](SubrefOp subref) -> FailureOr<Printed> {
        FailureOr<Printed> ref = printExpr(subref.getRef());
        FailureOr<Printed> index = printExpr(subref.getIndex());
        if (failed(ref) || failed(index)) {
          return failure();
        }
        return atom(ref->text + "[" + index->text + "]");
      })
      .Case([&](QubitIndexOp qubit) -> FailureOr<Printed> {
        FailureOr<Printed> reg = printExpr(qubit.getReg());
        FailureOr<Printed> index = printExpr(qubit.getIndex());
        if (failed(reg) || failed(index)) {
          return failure();
        }
        return atom(reg->text + "[" + index->text + "]");
      })
      .Case([&](PhysicalQubitOp qubit) { return atom("$" + std::to_string(qubit.getIndex())); })
      .Case([&](QubitDeclOp decl) { return atom(decl.getName().str()); })
      .Case([&](DeclareOp decl) { return atom(decl.getName().str()); })
      .Case([&](MeasureOp measure) -> FailureOr<Printed> {
        FailureOr<Printed> qubits = printExpr(measure.getQubits());
        if (failed(qubits)) {
          return failure();
        }
        return atom("measure " + qubits->text);
      })
      .Default([](Operation* other) -> FailureOr<Printed> {
        return other->emitOpError() << "cannot be exported to OpenQASM";
      });
}

LogicalResult qcc::oq3::exportOpenQASM(Operation* op, llvm::raw_ostream& os) {
  // Nothing is written unless the whole program can be exported.
  std::string text;
  llvm::raw_string_ostream buffer(text);
  if (failed(Exporter(buffer).run(op))) {
    return failure();
  }
  os << text;
  return success();
}

void qcc::oq3::registerExportOpenQASMTranslation() {
  static const TranslateFromMLIRRegistration registration(
      "export-openqasm", "Export a program of the oq3 dialect to OpenQASM 3",
      [](Operation* op, llvm::raw_ostream& os) { return exportOpenQASM(op, os); },
      [](DialectRegistry& registry) { registry.insert<OQ3Dialect, QccDialect, func::FuncDialect>(); });
}
