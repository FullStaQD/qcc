// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/OQ3/Import/Import.h"

#include "qcc/Dialect/OQ3/IR/OQ3.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "Lexer.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Tools/mlir-translate/Translation.h"

#include "llvm/ADT/APInt.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/SourceMgr.h"

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

using namespace mlir;
using namespace qcc;
using namespace qcc::oq3;
using namespace qcc::oq3::detail;
using llvm::SMLoc;

namespace {

/// A name in scope.
struct Binding {
  enum class Kind : uint8_t { Qubit, Variable };
  Kind kind;
  /// The qubit reference or register, or the storage of the variable.
  Value value;
  /// Where the name is declared, possibly in another file.
  Location loc;
};

/// An expression value and where it starts in the source.
struct Expr {
  Value value;
  SMLoc loc;

  [[nodiscard]] Type getType() const { return value.getType(); }
};

} // namespace

/// Returns the OpenQASM spelling of `type`, for diagnostics.
static std::string describeType(Type type) {
  auto withSize = [](StringRef base, int64_t size) { return (base + "[" + std::to_string(size) + "]").str(); };
  return TypeSwitch<Type, std::string>(type)
      .Case([](QubitRefType) { return "qubit"; })
      .Case([&](QRegType reg) { return withSize("qubit", reg.getSize()); })
      .Case([](BitType) { return "bit"; })
      .Case([&](BitsType bits) { return withSize("bit", bits.getSize()); })
      .Case([](UnsizedIntType) { return "int"; })
      .Case([](UnsizedFloatType) { return "float"; })
      .Case([](AngleType) { return "angle"; })
      .Default([](Type other) {
        std::string result;
        llvm::raw_string_ostream os(result);
        os << other;
        return result;
      });
}

/// Returns the math constant that `name` spells.
static std::optional<MathConstantKind> lookupMathConstant(StringRef name) {
  return llvm::StringSwitch<std::optional<MathConstantKind>>(name)
      .Cases({"pi", "π"}, MathConstantKind::Pi)
      .Cases({"tau", "τ"}, MathConstantKind::Tau)
      .Cases({"euler", "ℯ"}, MathConstantKind::Euler)
      .Default(std::nullopt);
}

/// Whether `name` is one of the spec's built-in functions.
static bool isBuiltinFunction(StringRef name) {
  return llvm::is_contained({"arccos", "arcsin", "arctan", "ceiling", "cos", "exp", "floor", "log", "mod", "popcount",
                             "pow", "rotl", "rotr", "sin", "sqrt", "tan", "real", "imag", "sizeof"},
                            name);
}

/// Returns `text` without the digit separators `_`.
static std::string withoutSeparators(StringRef text) {
  std::string result;
  llvm::copy_if(text, std::back_inserter(result), [](char c) { return c != '_'; });
  return result;
}

namespace {

/// Imports one OpenQASM program, including the files it includes.
class Importer {
public:
  Importer(llvm::SourceMgr& sourceMgr, MLIRContext* context, const ImportOptions& options)
      : sourceMgr(sourceMgr), context(context), options(options), builder(context) {}

  OwningOpRef<ModuleOp> run();

private:
  //===--------------------------------------------------------------------===//
  // Files and tokens
  //===--------------------------------------------------------------------===//

  /// The state of parsing one file.
  struct FileState {
    unsigned bufferId = 0;
    std::unique_ptr<Lexer> lexer;
    Token token;
    /// The end of the previous token.
    SMLoc previousEnd;
    /// The include whose file this is, if any.
    std::optional<int64_t> includeId;
    std::optional<Location> includeLoc;
  };

  Location getLoc(SMLoc loc) {
    const auto [line, column] = sourceMgr.getLineAndColumn(loc, file.bufferId);
    const StringRef filename = sourceMgr.getMemoryBuffer(file.bufferId)->getBufferIdentifier();
    Location fileLoc = FileLineColLoc::get(context, filename, line, column);
    return file.includeLoc ? CallSiteLoc::get(fileLoc, *file.includeLoc) : fileLoc;
  }
  InFlightDiagnostic emitError(SMLoc loc) { return mlir::emitError(getLoc(loc)); }
  InFlightDiagnostic emitError(SMLoc loc, const Twine& message) { return mlir::emitError(getLoc(loc), message); }

  /// Reports that the construct at `loc` is valid OpenQASM, but not supported by the importer yet.
  InFlightDiagnostic emitUnsupported(SMLoc loc, StringRef construct) {
    return emitError(loc) << construct << " are not supported yet";
  }

  /// Reports the current token as unexpected.
  InFlightDiagnostic emitUnexpected(StringRef expected) {
    if (file.token.is(TokenKind::Error)) {
      return emitError(file.token.getLoc()) << file.token.message;
    }
    if (file.token.is(TokenKind::Eof)) {
      return emitError(file.token.getLoc()) << "expected " << expected << ", got the end of the file";
    }
    return emitError(file.token.getLoc()) << "expected " << expected << ", got '" << file.token.spelling << "'";
  }

  [[nodiscard]] const Token& token() const { return file.token; }

  void consume() {
    file.previousEnd = file.token.getEndLoc();
    file.token = file.lexer->lex();
  }

  bool consumeIf(TokenKind kind) {
    if (!token().is(kind)) {
      return false;
    }
    consume();
    return true;
  }

  LogicalResult expect(TokenKind kind, StringRef expected) {
    if (!consumeIf(kind)) {
      return emitUnexpected(expected);
    }
    return success();
  }

  FailureOr<std::pair<StringRef, SMLoc>> expectIdentifier(StringRef expected) {
    if (!token().is(TokenKind::Identifier)) {
      return emitUnexpected(expected);
    }
    std::pair<StringRef, SMLoc> result{token().spelling, token().getLoc()};
    consume();
    return result;
  }

  //===--------------------------------------------------------------------===//
  // Statements
  //===--------------------------------------------------------------------===//

  LogicalResult parseFile(bool isMainFile);
  LogicalResult parseVersion();
  FailureOr<Operation*> parseStatement();
  FailureOr<Operation*> parsePragma();
  FailureOr<Operation*> parseInclude();
  FailureOr<Operation*> parseQubitDeclaration();
  FailureOr<Operation*> parseQregDeclaration();
  FailureOr<Operation*> parseBitDeclaration();
  FailureOr<Operation*> parseCregDeclaration();
  FailureOr<Operation*> parseMeasureStatement();
  FailureOr<Operation*> parseReset();
  FailureOr<Operation*> parseBarrier();
  FailureOr<Operation*> parseIdentifierStatement();
  FailureOr<Operation*> parseAssignment();
  FailureOr<Operation*> parseGateCall(StringRef name, SMLoc nameLoc);

  /// Checks that `name` can be declared now.
  LogicalResult checkDeclarable(StringRef name, SMLoc loc);
  void declare(StringRef name, Binding binding) { scope.insert_or_assign(name, binding); }

  //===--------------------------------------------------------------------===//
  // Includes
  //===--------------------------------------------------------------------===//

  LogicalResult includeStandardGates(StringRef path, SMLoc loc);
  /// Searches the include file `path` in the directory of the including file, then in the include directories. Returns
  /// the file and the path it was found at, or null if there is none.
  std::pair<std::unique_ptr<llvm::MemoryBuffer>, std::string> findIncludeFile(StringRef path);
  LogicalResult includeFile(StringRef path, SMLoc loc);

  //===--------------------------------------------------------------------===//
  // Expressions and operands
  //===--------------------------------------------------------------------===//

  FailureOr<Expr> parseExpression() { return parseBinary(/*minPrecedence=*/1); }
  FailureOr<Expr> parseBinary(unsigned minPrecedence);
  FailureOr<Expr> parseUnary();
  FailureOr<Expr> parsePrimary();
  FailureOr<Expr> parseIntegerLiteral();
  FailureOr<Expr> parseIdentifierExpression();
  FailureOr<Expr> parseMeasureExpression();
  FailureOr<SmallVector<Expr>> parseExpressionList(TokenKind end);

  FailureOr<Expr> buildBinary(BinaryKind kind, Expr lhs, Expr rhs, SMLoc opLoc);

  /// Parses `[index]` after a register or variable named `name` of `size` elements, and checks a constant index.
  FailureOr<Expr> parseIndex(StringRef name, int64_t size);

  /// Parses a designator `[size]` and returns its value and the evaluated size.
  FailureOr<std::pair<Value, int64_t>> parseDesignator();

  FailureOr<Expr> parseGateOperand();
  FailureOr<SmallVector<Expr>> parseGateOperandList();

  /// Parses an assignment target: a variable `c` or a bit of a register `c[i]`.
  FailureOr<Expr> parseLValue();

  /// Converts `expr` implicitly to `type`, for the use described by `context`.
  FailureOr<Value> coerce(Expr expr, Type type, StringRef context);

  // The importer is a short-lived helper that its caller outlives, so it refers to the caller's state.
  llvm::SourceMgr& sourceMgr; // NOLINT(cppcoreguidelines-avoid-const-or-ref-data-members)
  MLIRContext* context;
  const ImportOptions& options; // NOLINT(cppcoreguidelines-avoid-const-or-ref-data-members)
  OpBuilder builder;

  ModuleOp module;
  Block* body = nullptr;
  FileState file;
  /// Whether the version line has been seen in the main file.
  bool seenVersion = false;

  /// The names in scope. A program has a single scope so far.
  llvm::StringMap<Binding> scope;
  /// Where `stdgates.inc` was included, if it was.
  std::optional<Location> standardGatesIncludeLoc;
  int64_t nextIncludeId = 0;
  /// The real paths of the files being parsed, outermost first.
  SmallVector<std::string> fileStack;
};

} // namespace

//===----------------------------------------------------------------------===//
// Program
//===----------------------------------------------------------------------===//

OwningOpRef<ModuleOp> Importer::run() {
  const unsigned mainBuffer = sourceMgr.getMainFileID();
  file.bufferId = mainBuffer;
  file.lexer = std::make_unique<Lexer>(sourceMgr.getMemoryBuffer(mainBuffer)->getBuffer());

  const Location startLoc = getLoc(SMLoc::getFromPointer(file.lexer->getBuffer().begin()));
  OwningOpRef<ModuleOp> owningModule = ModuleOp::create(startLoc);
  module = *owningModule;

  builder.setInsertionPointToEnd(module.getBody());
  auto entry = func::FuncOp::create(builder, startLoc, "main", builder.getFunctionType({}, {}));
  entry->setAttr(QccDialect::EntryPointAttrHelper::getNameStr(), builder.getUnitAttr());
  body = entry.addEntryBlock();
  builder.setInsertionPointToEnd(body);

  SmallString<256> realPath;
  if (!llvm::sys::fs::real_path(sourceMgr.getMemoryBuffer(mainBuffer)->getBufferIdentifier(), realPath)) {
    fileStack.emplace_back(realPath);
  }

  if (failed(parseFile(/*isMainFile=*/true))) {
    return nullptr;
  }

  func::ReturnOp::create(builder, getLoc(token().getLoc()));
  if (!seenVersion) {
    module->setAttr(OQ3Dialect::VersionAttrHelper::getNameStr(),
                    VersionAttr::get(context, defaultMajorVersion, defaultMinorVersion));
  }

  if (failed(verify(module))) {
    return nullptr;
  }
  return owningModule;
}

LogicalResult Importer::parseFile(bool isMainFile) {
  consume();
  if (isMainFile && token().is(TokenKind::KwOpenQASM)) {
    if (failed(parseVersion())) {
      return failure();
    }
  } else if (token().is(TokenKind::KwOpenQASM)) {
    return emitError(token().getLoc(), "an included file cannot have a version line");
  } else if (isMainFile) {
    mlir::emitWarning(getLoc(token().getLoc())) << "the program has no version line; assuming 'OPENQASM "
                                                << defaultMajorVersion << "." << defaultMinorVersion << ";'";
  }

  while (!token().is(TokenKind::Eof)) {
    if (failed(parseStatement())) {
      return failure();
    }
  }
  return success();
}

LogicalResult Importer::parseVersion() {
  consume();

  const StringRef text = token().spelling;
  if (!token().is(TokenKind::IntegerLiteral) && !token().is(TokenKind::FloatLiteral)) {
    return emitUnexpected("a version number");
  }
  const auto [majorText, minorText] = text.split('.');
  unsigned major = 0;
  unsigned minor = 0;
  if (majorText.getAsInteger(10, major) || (text.contains('.') && minorText.getAsInteger(10, minor))) {
    return emitError(token().getLoc()) << "invalid version number '" << text << "'";
  }
  if (major != 3 || minor > devMinorVersion) {
    return emitError(token().getLoc()) << "OpenQASM " << text
                                       << " is not supported; supported versions are 3.0, 3.1, and 3.2";
  }
  if (minor == devMinorVersion && !options.allowDevVersion) {
    InFlightDiagnostic diag = emitError(token().getLoc()) << "OpenQASM " << text << " is not released yet";
    diag.attachNote() << "qcc implements the development specification as of " << devSpecDate << " (" << devSpecCommit
                      << "), which may still change; use --oq3-allow-dev-version to import the "
                      << "program anyway";
    return diag;
  }
  consume();
  if (failed(expect(TokenKind::Semicolon, "';' after the version"))) {
    return failure();
  }

  module->setAttr(OQ3Dialect::VersionAttrHelper::getNameStr(), VersionAttr::get(context, major, minor));
  seenVersion = true;
  return success();
}

//===----------------------------------------------------------------------===//
// Statements
//===----------------------------------------------------------------------===//

FailureOr<Operation*> Importer::parseStatement() {
  SmallVector<Attribute> annotations;
  while (token().is(TokenKind::Annotation)) {
    const StringRef name = token().spelling.drop_front();
    const StringRef content = file.lexer->lexRestOfLine();
    consume();
    file.previousEnd = SMLoc::getFromPointer(content.end());
    annotations.push_back(AnnotationAttr::get(context, name, content));
  }
  if (!annotations.empty() &&
      (token().is(TokenKind::Eof) || token().is(TokenKind::KwPragma) || token().is(TokenKind::RBrace))) {
    return emitError(token().getLoc(), "annotations must be followed by a statement");
  }

  const SMLoc loc = token().getLoc();
  FailureOr<Operation*> statement = failure();
  switch (token().kind) {
  case TokenKind::KwPragma:
    statement = parsePragma();
    break;
  case TokenKind::KwInclude:
    statement = parseInclude();
    break;
  case TokenKind::KwQubit:
    statement = parseQubitDeclaration();
    break;
  case TokenKind::KwQreg:
    statement = parseQregDeclaration();
    break;
  case TokenKind::KwBit:
    statement = parseBitDeclaration();
    break;
  case TokenKind::KwCreg:
    statement = parseCregDeclaration();
    break;
  case TokenKind::KwMeasure:
    statement = parseMeasureStatement();
    break;
  case TokenKind::KwReset:
    statement = parseReset();
    break;
  case TokenKind::KwBarrier:
    statement = parseBarrier();
    break;
  case TokenKind::KwGphase:
    consume();
    statement = parseGateCall("gphase", loc);
    break;
  case TokenKind::Identifier:
    statement = parseIdentifierStatement();
    break;
  case TokenKind::KwOpenQASM:
    return emitError(loc, "the version line must be the first statement of the program");
  case TokenKind::KwInv:
  case TokenKind::KwPow:
  case TokenKind::KwCtrl:
  case TokenKind::KwNegctrl:
    return emitUnsupported(loc, "gate modifiers");
  case TokenKind::KwGate:
    return emitUnsupported(loc, "gate definitions");
  case TokenKind::KwDef:
    return emitUnsupported(loc, "subroutine definitions");
  case TokenKind::KwExtern:
    return emitUnsupported(loc, "extern declarations");
  case TokenKind::KwLet:
    return emitUnsupported(loc, "alias declarations ('let')");
  case TokenKind::KwConst:
    return emitUnsupported(loc, "constant declarations");
  case TokenKind::KwInput:
  case TokenKind::KwOutput:
    return emitUnsupported(loc, "input and output declarations");
  case TokenKind::KwBool:
  case TokenKind::KwInt:
  case TokenKind::KwUint:
  case TokenKind::KwFloat:
  case TokenKind::KwAngle:
  case TokenKind::KwComplex:
  case TokenKind::KwArray:
  case TokenKind::KwDuration:
  case TokenKind::KwStretch:
    return emitError(loc) << "declarations of type '" << token().spelling << "' are not supported yet";
  case TokenKind::KwIf:
  case TokenKind::KwFor:
  case TokenKind::KwWhile:
  case TokenKind::KwSwitch:
  case TokenKind::KwBreak:
  case TokenKind::KwContinue:
  case TokenKind::KwReturn:
  case TokenKind::KwEnd:
  case TokenKind::LBrace:
    return emitError(loc) << "control flow ('" << token().spelling << "') is not supported yet";
  case TokenKind::KwBox:
  case TokenKind::KwDelay:
  case TokenKind::KwNop:
    return emitError(loc) << "timing instructions ('" << token().spelling << "') are not supported yet";
  case TokenKind::KwCal:
  case TokenKind::KwDefcal:
  case TokenKind::KwDefcalgrammar:
    return emitUnsupported(loc, "calibrations");
  default:
    return emitUnexpected("a statement");
  }

  if (succeeded(statement) && !annotations.empty()) {
    (*statement)->setAttr(OQ3Dialect::AnnotationsAttrHelper::getNameStr(), builder.getArrayAttr(annotations));
  }
  return statement;
}

FailureOr<Operation*> Importer::parsePragma() {
  const SMLoc loc = token().getLoc();
  const StringRef text = file.lexer->lexRestOfLine();
  if (text.empty()) {
    return emitError(loc, "expected the content of the pragma on the same line");
  }
  consume();
  file.previousEnd = SMLoc::getFromPointer(text.end());
  return PragmaOp::create(builder, getLoc(loc), text).getOperation();
}

FailureOr<Operation*> Importer::parseInclude() {
  const SMLoc loc = token().getLoc();
  consume();
  if (!token().is(TokenKind::StringLiteral)) {
    return emitUnexpected("a file name in quotes");
  }
  const StringRef path = token().spelling.drop_front().drop_back();
  consume();
  if (failed(expect(TokenKind::Semicolon, "';'"))) {
    return failure();
  }

  if (path == standardGatesInclude) {
    if (failed(includeStandardGates(path, loc))) {
      return failure();
    }
    return &body->back();
  }

  Operation* before = body->empty() ? nullptr : &body->back();
  if (failed(includeFile(path, loc))) {
    return failure();
  }
  // The include op is the first one after `before`; the included file's statements follow it.
  return before != nullptr ? before->getNextNode() : &body->front();
}

LogicalResult Importer::includeStandardGates(StringRef path, SMLoc loc) {
  if (standardGatesIncludeLoc) {
    // The line of the first include, in its own file.
    Location first = *standardGatesIncludeLoc;
    if (auto callSite = dyn_cast<CallSiteLoc>(first)) {
      first = callSite.getCallee();
    }
    const unsigned line = isa<FileLineColLoc>(first) ? cast<FileLineColLoc>(first).getLine() : 0;
    InFlightDiagnostic diag = emitError(loc) << "'" << path << "' was already included at line " << line
                                             << "; its definitions would be redeclared";
    diag.attachNote(standardGatesIncludeLoc) << "the first include is here";
    return diag;
  }
  for (const auto& entry : scope) {
    if (lookupStandardGate(entry.first())) {
      InFlightDiagnostic diag = emitError(loc) << "'" << path << "' defines the gate '" << entry.first()
                                               << "', which is already declared";
      diag.attachNote(entry.second.loc) << "the declaration is here";
      return diag;
    }
  }
  // A `stdgates.inc` that is not found is described by the built-in signature table.
  if (findIncludeFile(path).first != nullptr) {
    // TODO: Read the file like any other include once gate definitions are supported. Until then, the built-in
    // signature table describes it as well.
  }
  IncludeOp::create(builder, getLoc(loc), path, nextIncludeId++);
  standardGatesIncludeLoc = getLoc(loc);
  return success();
}

std::pair<std::unique_ptr<llvm::MemoryBuffer>, std::string> Importer::findIncludeFile(StringRef path) {
  SmallVector<std::string> candidates;
  if (llvm::sys::path::is_absolute(path)) {
    candidates.emplace_back(path);
  } else {
    SmallString<256> local(
        llvm::sys::path::parent_path(sourceMgr.getMemoryBuffer(file.bufferId)->getBufferIdentifier()));
    llvm::sys::path::append(local, path);
    candidates.emplace_back(local);
    for (const std::string& dir : options.includeDirs) {
      SmallString<256> candidate(dir);
      llvm::sys::path::append(candidate, path);
      candidates.emplace_back(candidate);
    }
  }

  for (const std::string& candidate : candidates) {
    llvm::ErrorOr<std::unique_ptr<llvm::MemoryBuffer>> result = llvm::MemoryBuffer::getFile(candidate);
    if (result) {
      return {std::move(*result), candidate};
    }
  }
  return {nullptr, ""};
}

LogicalResult Importer::includeFile(StringRef path, SMLoc loc) {
  auto [buffer, foundPath] = findIncludeFile(path);
  if (!buffer) {
    return emitError(loc) << "cannot find the include file '" << path << "'";
  }

  SmallString<256> realPath;
  if (!llvm::sys::fs::real_path(foundPath, realPath) && llvm::is_contained(fileStack, realPath.str())) {
    return emitError(loc) << "including '" << path << "' here forms an include cycle";
  }

  const int64_t id = nextIncludeId++;
  auto include = IncludeOp::create(builder, getLoc(loc), path, id);

  // Parse the included file in place, in the same scope.
  FileState outer = std::move(file);
  const Location includeLoc = include.getLoc();
  file = FileState{};
  file.bufferId = sourceMgr.AddNewSourceBuffer(std::move(buffer), loc);
  file.lexer = std::make_unique<Lexer>(sourceMgr.getMemoryBuffer(file.bufferId)->getBuffer());
  file.includeId = id;
  file.includeLoc = includeLoc;
  fileStack.emplace_back(realPath);

  const LogicalResult result = parseFile(/*isMainFile=*/false);

  fileStack.pop_back();
  file = std::move(outer);
  if (failed(result)) {
    return failure();
  }

  // Everything the file produced comes from this include. Nested includes have tagged their own statements already.
  const StringRef tagName = OQ3Dialect::FromIncludeAttrHelper::getNameStr();
  for (Operation* op = include->getNextNode(); op != nullptr; op = op->getNextNode()) {
    if (!op->hasAttr(tagName)) {
      op->setAttr(tagName, builder.getI64IntegerAttr(id));
    }
  }
  return success();
}

LogicalResult Importer::checkDeclarable(StringRef name, SMLoc loc) {
  if (lookupMathConstant(name) || lookupBuiltinGate(name)) {
    return emitError(loc) << "'" << name << "' is a built-in name and cannot be declared";
  }
  if (auto it = scope.find(name); it != scope.end()) {
    InFlightDiagnostic diag = emitError(loc) << "'" << name << "' is already declared";
    diag.attachNote(it->second.loc) << "the previous declaration is here";
    return diag;
  }
  if (standardGatesIncludeLoc && lookupStandardGate(name)) {
    return emitError(loc) << "'" << name << "' is already defined as a gate by '" << standardGatesInclude << "'";
  }
  return success();
}

FailureOr<std::pair<Value, int64_t>> Importer::parseDesignator() {
  consume(); // [
  FailureOr<Expr> size = parseExpression();
  if (failed(size) || failed(expect(TokenKind::RBracket, "']'"))) {
    return failure();
  }
  if (!isa<UnsizedIntType>(size->getType())) {
    return emitError(size->loc) << "a size must be an integer, got '" << describeType(size->getType()) << "'";
  }
  const FailureOr<int64_t> value =
      evaluateConstantInt(size->value, [&](Operation* op) { return mlir::emitError(op->getLoc()); });
  if (failed(value)) {
    return emitError(size->loc, "a size must be a constant expression");
  }
  if (*value < 0) {
    return emitError(size->loc) << "a size must be non-negative, got " << *value;
  }
  return std::pair{size->value, *value};
}

FailureOr<Operation*> Importer::parseQubitDeclaration() {
  const SMLoc loc = token().getLoc();
  consume();
  Value designator;
  Type type = QubitRefType::get(context);
  if (token().is(TokenKind::LBracket)) {
    FailureOr<std::pair<Value, int64_t>> size = parseDesignator();
    if (failed(size)) {
      return failure();
    }
    designator = size->first;
    type = QRegType::get(context, size->second);
  }
  FailureOr<std::pair<StringRef, SMLoc>> name = expectIdentifier("the name of the qubit");
  if (failed(name) || failed(checkDeclarable(name->first, name->second)) ||
      failed(expect(TokenKind::Semicolon, "';'"))) {
    return failure();
  }
  auto decl = QubitDeclOp::create(builder, getLoc(loc), type, name->first, designator);
  declare(name->first, {.kind = Binding::Kind::Qubit, .value = decl.getResult(), .loc = getLoc(name->second)});
  return decl.getOperation();
}

FailureOr<Operation*> Importer::parseQregDeclaration() {
  const SMLoc loc = token().getLoc();
  consume();
  FailureOr<std::pair<StringRef, SMLoc>> name = expectIdentifier("the name of the register");
  if (failed(name) || failed(checkDeclarable(name->first, name->second))) {
    return failure();
  }
  Value designator;
  Type type = QubitRefType::get(context);
  if (token().is(TokenKind::LBracket)) {
    FailureOr<std::pair<Value, int64_t>> size = parseDesignator();
    if (failed(size)) {
      return failure();
    }
    designator = size->first;
    type = QRegType::get(context, size->second);
  }
  if (failed(expect(TokenKind::Semicolon, "';'"))) {
    return failure();
  }
  mlir::emitWarning(getLoc(loc)) << "'qreg' is deprecated; declare '" << name->first << "' with 'qubit"
                                 << (designator ? "[n]" : "") << " " << name->first << ";' instead";
  auto decl = QubitDeclOp::create(builder, getLoc(loc), type, name->first, designator);
  declare(name->first, {.kind = Binding::Kind::Qubit, .value = decl.getResult(), .loc = getLoc(name->second)});
  return decl.getOperation();
}

FailureOr<Operation*> Importer::parseBitDeclaration() {
  const SMLoc loc = token().getLoc();
  consume();
  Value designator;
  Type type = BitType::get(context);
  if (token().is(TokenKind::LBracket)) {
    FailureOr<std::pair<Value, int64_t>> size = parseDesignator();
    if (failed(size)) {
      return failure();
    }
    designator = size->first;
    type = BitsType::get(context, size->second);
  }
  FailureOr<std::pair<StringRef, SMLoc>> name = expectIdentifier("the name of the variable");
  if (failed(name) || failed(checkDeclarable(name->first, name->second))) {
    return failure();
  }

  Value init;
  if (consumeIf(TokenKind::Equals)) {
    FailureOr<Expr> value = token().is(TokenKind::KwMeasure) ? parseMeasureExpression() : parseExpression();
    if (failed(value)) {
      return failure();
    }
    FailureOr<Value> converted = coerce(*value, type, "initialize the variable with");
    if (failed(converted)) {
      return failure();
    }
    init = *converted;
  }
  if (failed(expect(TokenKind::Semicolon, "';'"))) {
    return failure();
  }
  auto decl = DeclareOp::create(builder, getLoc(loc), RefType::get(type), name->first, designator, init);
  declare(name->first, {.kind = Binding::Kind::Variable, .value = decl.getResult(), .loc = getLoc(name->second)});
  return decl.getOperation();
}

FailureOr<Operation*> Importer::parseCregDeclaration() {
  const SMLoc loc = token().getLoc();
  consume();
  FailureOr<std::pair<StringRef, SMLoc>> name = expectIdentifier("the name of the register");
  if (failed(name) || failed(checkDeclarable(name->first, name->second))) {
    return failure();
  }
  Value designator;
  Type type = BitType::get(context);
  if (token().is(TokenKind::LBracket)) {
    FailureOr<std::pair<Value, int64_t>> size = parseDesignator();
    if (failed(size)) {
      return failure();
    }
    designator = size->first;
    type = BitsType::get(context, size->second);
  }
  if (failed(expect(TokenKind::Semicolon, "';'"))) {
    return failure();
  }
  mlir::emitWarning(getLoc(loc)) << "'creg' is deprecated; declare '" << name->first << "' with 'bit"
                                 << (designator ? "[n]" : "") << " " << name->first << ";' instead";
  auto decl = DeclareOp::create(builder, getLoc(loc), RefType::get(type), name->first, designator, Value());
  declare(name->first, {.kind = Binding::Kind::Variable, .value = decl.getResult(), .loc = getLoc(name->second)});
  return decl.getOperation();
}

FailureOr<Operation*> Importer::parseMeasureStatement() {
  const SMLoc loc = token().getLoc();
  FailureOr<Expr> measurement = parseMeasureExpression();
  if (failed(measurement)) {
    return failure();
  }
  Operation* statement = measurement->value.getDefiningOp();
  if (consumeIf(TokenKind::Arrow)) {
    FailureOr<Expr> target = parseLValue();
    if (failed(target)) {
      return failure();
    }
    FailureOr<Value> value =
        coerce(*measurement, cast<RefType>(target->getType()).getElementType(), "store the measurement in");
    if (failed(value)) {
      return failure();
    }
    statement = RefStoreOp::create(builder, getLoc(loc), *value, target->value);
  }
  if (failed(expect(TokenKind::Semicolon, "';'"))) {
    return failure();
  }
  return statement;
}

FailureOr<Operation*> Importer::parseReset() {
  const SMLoc loc = token().getLoc();
  consume();
  FailureOr<Expr> qubits = parseGateOperand();
  if (failed(qubits) || failed(expect(TokenKind::Semicolon, "';'"))) {
    return failure();
  }
  return ResetOp::create(builder, getLoc(loc), qubits->value).getOperation();
}

FailureOr<Operation*> Importer::parseBarrier() {
  const SMLoc loc = token().getLoc();
  consume();
  SmallVector<Value> qubits;
  if (!token().is(TokenKind::Semicolon)) {
    FailureOr<SmallVector<Expr>> operands = parseGateOperandList();
    if (failed(operands)) {
      return failure();
    }
    qubits = llvm::map_to_vector(*operands, [](const Expr& operand) { return operand.value; });
  }
  if (failed(expect(TokenKind::Semicolon, "';'"))) {
    return failure();
  }
  return BarrierOp::create(builder, getLoc(loc), qubits).getOperation();
}

FailureOr<Operation*> Importer::parseIdentifierStatement() {
  const StringRef name = token().spelling;
  const SMLoc loc = token().getLoc();

  if (auto it = scope.find(name); it != scope.end()) {
    if (it->second.kind == Binding::Kind::Variable) {
      return parseAssignment();
    }
    return emitError(loc) << "expected a statement, but '" << name << "' is a qubit";
  }
  if (lookupMathConstant(name)) {
    return emitUnsupported(loc, "expression statements");
  }
  if (lookupBuiltinGate(name) || (standardGatesIncludeLoc && lookupStandardGate(name))) {
    consume();
    return parseGateCall(name, loc);
  }
  InFlightDiagnostic diag = emitError(loc) << "unknown name '" << name << "'";
  if (lookupStandardGate(name)) {
    diag.attachNote() << "'" << name << "' is a standard gate; it needs an earlier 'include \"" << standardGatesInclude
                      << "\";'";
  }
  return diag;
}

FailureOr<Operation*> Importer::parseAssignment() {
  const SMLoc loc = token().getLoc();
  FailureOr<Expr> target = parseLValue();
  if (failed(target)) {
    return failure();
  }
  if (token().is(TokenKind::CompoundAssign)) {
    return emitUnsupported(token().getLoc(), "compound assignments");
  }
  if (failed(expect(TokenKind::Equals, "'='"))) {
    return failure();
  }
  FailureOr<Expr> value = token().is(TokenKind::KwMeasure) ? parseMeasureExpression() : parseExpression();
  if (failed(value)) {
    return failure();
  }
  FailureOr<Value> converted = coerce(*value, cast<RefType>(target->getType()).getElementType(), "assign");
  if (failed(converted) || failed(expect(TokenKind::Semicolon, "';'"))) {
    return failure();
  }
  return RefStoreOp::create(builder, getLoc(loc), *converted, target->value).getOperation();
}

FailureOr<Operation*> Importer::parseGateCall(StringRef name, SMLoc nameLoc) {
  SmallVector<Expr> params;
  if (consumeIf(TokenKind::LParen)) {
    FailureOr<SmallVector<Expr>> list = parseExpressionList(TokenKind::RParen);
    if (failed(list)) {
      return failure();
    }
    params = std::move(*list);
  }
  if (token().is(TokenKind::LBracket)) {
    return emitUnsupported(token().getLoc(), "durations of gate calls");
  }
  SmallVector<Expr> qubits;
  if (!token().is(TokenKind::Semicolon)) {
    FailureOr<SmallVector<Expr>> list = parseGateOperandList();
    if (failed(list)) {
      return failure();
    }
    qubits = std::move(*list);
  }
  if (failed(expect(TokenKind::Semicolon, "';'"))) {
    return failure();
  }

  std::optional<GateSignature> signature = lookupBuiltinGate(name);
  if (!signature && standardGatesIncludeLoc) {
    signature = lookupStandardGate(name);
  }
  if (signature) {
    if (params.size() != signature->numParams) {
      return emitError(nameLoc) << "gate '" << name << "' takes " << signature->numParams << " parameter(s), got "
                                << params.size();
    }
    if (qubits.size() != signature->numQubits) {
      return emitError(nameLoc) << "gate '" << name << "' takes " << signature->numQubits << " qubit(s), got "
                                << qubits.size();
    }
  }

  // Registers broadcast, so they must agree in size.
  std::optional<Expr> firstRegister;
  for (const Expr& operand : qubits) {
    auto reg = dyn_cast<QRegType>(operand.getType());
    if (!reg) {
      continue;
    }
    if (firstRegister && cast<QRegType>(firstRegister->getType()).getSize() != reg.getSize()) {
      InFlightDiagnostic diag = emitError(operand.loc) << "a register of size " << reg.getSize()
                                                       << " cannot be broadcast together with one of size "
                                                       << cast<QRegType>(firstRegister->getType()).getSize();
      diag.attachNote(getLoc(firstRegister->loc)) << "the other register is here";
      return diag;
    }
    firstRegister = operand;
  }

  SmallVector<Value> paramValues;
  for (const Expr& param : params) {
    FailureOr<Value> angle = coerce(param, AngleType::get(context), "pass as a gate parameter");
    if (failed(angle)) {
      return failure();
    }
    paramValues.push_back(*angle);
  }
  const SmallVector<Value> qubitValues = llvm::map_to_vector(qubits, [](const Expr& qubit) { return qubit.value; });
  return GateCallOp::create(builder, getLoc(nameLoc), FlatSymbolRefAttr::get(context, name), paramValues, qubitValues)
      .getOperation();
}

//===----------------------------------------------------------------------===//
// Expressions
//===----------------------------------------------------------------------===//

/// The precedence of a supported binary operator, higher binds tighter, or nullopt.
static std::optional<std::pair<BinaryKind, unsigned>> getBinaryOperator(TokenKind kind) {
  switch (kind) {
  case TokenKind::Plus:
    return std::pair{BinaryKind::Add, 1U};
  case TokenKind::Minus:
    return std::pair{BinaryKind::Sub, 1U};
  case TokenKind::Asterisk:
    return std::pair{BinaryKind::Mul, 2U};
  case TokenKind::Slash:
    return std::pair{BinaryKind::Div, 2U};
  default:
    return std::nullopt;
  }
}

/// Whether `kind` is a binary operator of the language that is not supported yet.
static bool isUnsupportedBinaryOperator(TokenKind kind) {
  switch (kind) {
  case TokenKind::Percent:
  case TokenKind::DoubleAsterisk:
  case TokenKind::ShiftLeft:
  case TokenKind::ShiftRight:
  case TokenKind::Less:
  case TokenKind::LessEqual:
  case TokenKind::Greater:
  case TokenKind::GreaterEqual:
  case TokenKind::EqualEqual:
  case TokenKind::NotEqual:
  case TokenKind::Ampersand:
  case TokenKind::Pipe:
  case TokenKind::Caret:
  case TokenKind::DoubleAmpersand:
  case TokenKind::DoublePipe:
  case TokenKind::DoublePlus:
    return true;
  default:
    return false;
  }
}

FailureOr<Expr> Importer::parseBinary(unsigned minPrecedence) {
  FailureOr<Expr> lhs = parseUnary();
  if (failed(lhs)) {
    return failure();
  }
  while (true) {
    if (isUnsupportedBinaryOperator(token().kind)) {
      return emitError(token().getLoc()) << "the operator '" << token().spelling << "' is not supported yet";
    }
    const std::optional<std::pair<BinaryKind, unsigned>> op = getBinaryOperator(token().kind);
    if (!op || op->second < minPrecedence) {
      return lhs;
    }
    const SMLoc opLoc = token().getLoc();
    consume();
    // All supported operators are left-associative.
    FailureOr<Expr> rhs = parseBinary(op->second + 1);
    if (failed(rhs)) {
      return failure();
    }
    lhs = buildBinary(op->first, *lhs, *rhs, opLoc);
    if (failed(lhs)) {
      return failure();
    }
  }
}

FailureOr<Expr> Importer::buildBinary(BinaryKind kind, Expr lhs, Expr rhs, SMLoc opLoc) {
  const Location loc = getLoc(opLoc);
  Type lhsType = lhs.getType();
  Type rhsType = rhs.getType();
  Type resultType;

  if (lhsType == rhsType && (isa<UnsizedIntType, UnsizedFloatType>(lhsType) ||
                             (isa<AngleType>(lhsType) && (kind == BinaryKind::Add || kind == BinaryKind::Sub)))) {
    // Angles only add to and subtract from angles.
    resultType = lhsType;
  } else if (isa<UnsizedIntType>(lhsType) && isa<UnsizedFloatType>(rhsType)) {
    lhs.value = CastOp::create(builder, loc, rhsType, lhs.value, /*implicit=*/true);
    resultType = rhsType;
  } else if (isa<UnsizedFloatType>(lhsType) && isa<UnsizedIntType>(rhsType)) {
    rhs.value = CastOp::create(builder, loc, lhsType, rhs.value, /*implicit=*/true);
    resultType = lhsType;
  } else if ((kind == BinaryKind::Mul && isa<AngleType>(lhsType) && isa<UnsizedIntType>(rhsType)) ||
             (kind == BinaryKind::Mul && isa<UnsizedIntType>(lhsType) && isa<AngleType>(rhsType)) ||
             (kind == BinaryKind::Div && isa<AngleType>(lhsType) && isa<UnsizedIntType>(rhsType))) {
    resultType = AngleType::get(context);
  } else {
    return emitError(opLoc) << "the operator '" << StringRef(opLoc.getPointer(), 1) << "' cannot be applied to '"
                            << describeType(lhsType) << "' and '" << describeType(rhsType) << "'";
  }

  auto binary = BinaryOp::create(builder, loc, resultType, kind, lhs.value, rhs.value);
  return Expr{.value = binary, .loc = lhs.loc};
}

FailureOr<Expr> Importer::parseUnary() {
  const SMLoc loc = token().getLoc();
  if (token().is(TokenKind::Tilde) || token().is(TokenKind::Exclamation)) {
    return emitError(loc) << "the operator '" << token().spelling << "' is not supported yet";
  }
  if (!consumeIf(TokenKind::Minus)) {
    return parsePrimary();
  }
  FailureOr<Expr> operand = parseUnary();
  if (failed(operand)) {
    return failure();
  }
  if (!isa<UnsizedIntType, UnsizedFloatType, AngleType>(operand->getType())) {
    return emitError(loc) << "the operator '-' cannot be applied to '" << describeType(operand->getType()) << "'";
  }
  auto negation = UnaryOp::create(builder, getLoc(loc), UnaryKind::Neg, operand->value);
  return Expr{.value = negation, .loc = loc};
}

FailureOr<Expr> Importer::parsePrimary() {
  const SMLoc loc = token().getLoc();
  switch (token().kind) {
  case TokenKind::LParen: {
    consume();
    FailureOr<Expr> inner = parseExpression();
    if (failed(inner) || failed(expect(TokenKind::RParen, "')'"))) {
      return failure();
    }
    return Expr{.value = inner->value, .loc = loc};
  }
  case TokenKind::IntegerLiteral:
    return parseIntegerLiteral();
  case TokenKind::FloatLiteral: {
    const std::string text = withoutSeparators(token().spelling);
    consume();
    auto constant =
        ConstantOp::create(builder, getLoc(loc), FloatLiteralAttr::get(context, text, UnsizedFloatType::get(context)));
    return Expr{.value = constant, .loc = loc};
  }
  case TokenKind::StringLiteral: {
    const StringRef spelling = token().spelling;
    const StringRef bits = spelling.drop_front().drop_back();
    const bool isBitstring = spelling.front() == '"' && !bits.empty() && bits.front() != '_' && bits.back() != '_' &&
                             !bits.contains("__") &&
                             llvm::all_of(bits, [](char c) { return c == '0' || c == '1' || c == '_'; });
    if (!isBitstring) {
      return emitError(loc) << "expected an expression; a string in an expression must be a bitstring such as "
                               "\"0101\"";
    }
    const std::string text = withoutSeparators(bits);
    consume();
    const Type type = BitsType::get(context, static_cast<int64_t>(text.size()));
    auto constant = ConstantOp::create(
        builder, getLoc(loc),
        BitstringAttr::get(context, APInt(static_cast<unsigned>(text.size()), text, /*radix=*/2), type));
    return Expr{.value = constant, .loc = loc};
  }
  case TokenKind::Identifier:
    return parseIdentifierExpression();
  case TokenKind::KwTrue:
  case TokenKind::KwFalse:
    return emitUnsupported(loc, "boolean literals");
  case TokenKind::ImaginaryLiteral:
    return emitUnsupported(loc, "imaginary literals");
  case TokenKind::TimingLiteral:
    return emitUnsupported(loc, "duration literals");
  case TokenKind::KwDurationof:
    return emitUnsupported(loc, "'durationof' expressions");
  case TokenKind::KwMeasure:
    return emitError(loc, "a measurement can only be assigned, not be part of an expression");
  case TokenKind::HardwareQubit:
    return emitError(loc, "a physical qubit cannot be used in an expression");
  case TokenKind::KwBool:
  case TokenKind::KwBit:
  case TokenKind::KwInt:
  case TokenKind::KwUint:
  case TokenKind::KwFloat:
  case TokenKind::KwAngle:
  case TokenKind::KwComplex:
  case TokenKind::KwArray:
  case TokenKind::KwDuration:
    return emitUnsupported(loc, "casts");
  case TokenKind::LBrace:
    return emitUnsupported(loc, "array literals and index sets");
  default:
    return emitUnexpected("an expression");
  }
}

FailureOr<Expr> Importer::parseIntegerLiteral() {
  const SMLoc loc = token().getLoc();
  StringRef digits = token().spelling;
  unsigned radix = 10;
  if (digits.size() > 2 && digits[0] == '0' && llvm::isAlpha(digits[1])) {
    switch (digits[1]) {
    case 'b':
    case 'B':
      radix = 2;
      break;
    case 'o':
      radix = 8;
      break;
    default:
      radix = 16;
      break;
    }
    digits = digits.drop_front(2);
  }
  APInt value;
  if (StringRef(withoutSeparators(digits)).getAsInteger(radix, value)) {
    return emitError(loc, "invalid integer literal");
  }
  consume();
  auto constant = ConstantOp::create(builder, getLoc(loc), IntLiteralAttr::get(value, UnsizedIntType::get(context)));
  return Expr{.value = constant, .loc = loc};
}

FailureOr<Expr> Importer::parseIdentifierExpression() {
  const StringRef name = token().spelling;
  const SMLoc loc = token().getLoc();
  consume();

  if (token().is(TokenKind::LParen)) {
    if (isBuiltinFunction(name)) {
      return emitUnsupported(loc, "built-in functions");
    }
    return emitError(loc) << "'" << name << "' is not a subroutine";
  }
  if (token().is(TokenKind::LBracket)) {
    return emitUnsupported(token().getLoc(), "indexing of classical values");
  }

  if (const auto constant = lookupMathConstant(name)) {
    auto op = MathConstantOp::create(builder, getLoc(loc), UnsizedFloatType::get(context), *constant);
    return Expr{.value = op, .loc = loc};
  }
  if (auto it = scope.find(name); it != scope.end()) {
    if (it->second.kind == Binding::Kind::Qubit) {
      return emitError(loc) << "the qubit '" << name << "' cannot be used in an expression";
    }
    auto load = RefLoadOp::create(builder, getLoc(loc), it->second.value);
    return Expr{.value = load, .loc = loc};
  }
  return emitError(loc) << "unknown name '" << name << "'";
}

FailureOr<SmallVector<Expr>> Importer::parseExpressionList(TokenKind end) {
  SmallVector<Expr> list;
  while (!consumeIf(end)) {
    FailureOr<Expr> element = parseExpression();
    if (failed(element)) {
      return failure();
    }
    list.push_back(*element);
    if (!consumeIf(TokenKind::Comma)) {
      if (failed(expect(end, "',' or ')'"))) {
        return failure();
      }
      break;
    }
  }
  return list;
}

FailureOr<Expr> Importer::parseMeasureExpression() {
  const SMLoc loc = token().getLoc();
  consume();
  FailureOr<Expr> qubits = parseGateOperand();
  if (failed(qubits)) {
    return failure();
  }
  Type resultType = BitType::get(context);
  if (auto reg = dyn_cast<QRegType>(qubits->getType())) {
    resultType = BitsType::get(context, reg.getSize());
  }
  auto measure = MeasureOp::create(builder, getLoc(loc), resultType, qubits->value);
  return Expr{.value = measure, .loc = loc};
}

FailureOr<Value> Importer::coerce(Expr expr, Type type, StringRef context) {
  const Type from = expr.getType();
  const Location loc = getLoc(expr.loc);
  if (from == type) {
    return expr.value;
  }
  if (isa<UnsizedIntType>(from) && isa<UnsizedFloatType>(type)) {
    return CastOp::create(builder, loc, type, expr.value, /*implicit=*/true).getResult();
  }
  if (isa<UnsizedFloatType>(from) && isa<AngleType>(type)) {
    return CastOp::create(builder, loc, type, expr.value, /*implicit=*/true).getResult();
  }
  if (isa<UnsizedIntType>(from) && isa<AngleType>(type)) {
    // An integer is no angle, but it is a float, which is.
    Value asFloat = CastOp::create(builder, loc, UnsizedFloatType::get(this->context), expr.value, /*implicit=*/true);
    return CastOp::create(builder, loc, type, asFloat, /*implicit=*/true).getResult();
  }
  if (isa<UnsizedIntType>(from) && isa<BitType>(type)) {
    const FailureOr<int64_t> value = evaluateConstantInt(expr.value);
    if (failed(value) || (*value != 0 && *value != 1)) {
      return emitError(expr.loc) << "only the integers 0 and 1 convert to a 'bit' implicitly";
    }
    return CastOp::create(builder, loc, type, expr.value, /*implicit=*/true).getResult();
  }
  return emitError(expr.loc) << "cannot " << context << " a value of type '" << describeType(from) << "' a '"
                             << describeType(type) << "'";
}

//===----------------------------------------------------------------------===//
// Operands
//===----------------------------------------------------------------------===//

FailureOr<Expr> Importer::parseIndex(StringRef name, int64_t size) {
  consume(); // [
  if (token().is(TokenKind::LBrace) || token().is(TokenKind::Colon)) {
    return emitUnsupported(token().getLoc(), "slices and index sets");
  }
  FailureOr<Expr> index = parseExpression();
  if (failed(index)) {
    return failure();
  }
  if (token().is(TokenKind::Colon) || token().is(TokenKind::Comma)) {
    return emitUnsupported(token().getLoc(), "slices and multiple indices");
  }
  if (failed(expect(TokenKind::RBracket, "']'"))) {
    return failure();
  }
  if (!isa<UnsizedIntType>(index->getType())) {
    return emitError(index->loc) << "an index must be an integer, got '" << describeType(index->getType()) << "'";
  }
  const FailureOr<int64_t> value = evaluateConstantInt(index->value);
  if (succeeded(value) && (*value < -size || *value >= size)) {
    return emitError(index->loc) << "index " << *value << " is out of range for '" << name << "' of size " << size;
  }
  return index;
}

FailureOr<Expr> Importer::parseGateOperand() {
  const SMLoc loc = token().getLoc();
  if (token().is(TokenKind::HardwareQubit)) {
    int64_t index = 0;
    if (token().spelling.drop_front().getAsInteger(10, index)) {
      return emitError(loc, "invalid physical qubit");
    }
    consume();
    auto qubit = PhysicalQubitOp::create(builder, getLoc(loc), QubitRefType::get(context), index);
    return Expr{.value = qubit, .loc = loc};
  }

  FailureOr<std::pair<StringRef, SMLoc>> name = expectIdentifier("a qubit");
  if (failed(name)) {
    return failure();
  }
  Value qubits;
  if (auto it = scope.find(name->first); it != scope.end()) {
    if (it->second.kind != Binding::Kind::Qubit) {
      return emitError(loc) << "'" << name->first << "' is not a qubit";
    }
    qubits = it->second.value;
  } else {
    return emitError(loc) << "unknown qubit '" << name->first << "'";
  }

  if (!token().is(TokenKind::LBracket)) {
    return Expr{.value = qubits, .loc = loc};
  }
  if (isa<QubitRefType>(qubits.getType())) {
    return emitError(token().getLoc()) << "'" << name->first << "' is a single qubit and cannot be indexed";
  }
  FailureOr<Expr> index = parseIndex(name->first, cast<QRegType>(qubits.getType()).getSize());
  if (failed(index)) {
    return failure();
  }
  auto qubit = QubitIndexOp::create(builder, getLoc(loc), qubits, index->value);
  return Expr{.value = qubit, .loc = loc};
}

FailureOr<SmallVector<Expr>> Importer::parseGateOperandList() {
  SmallVector<Expr> operands;
  do {
    FailureOr<Expr> operand = parseGateOperand();
    if (failed(operand)) {
      return failure();
    }
    operands.push_back(*operand);
  } while (consumeIf(TokenKind::Comma) && !token().is(TokenKind::Semicolon));
  return operands;
}

FailureOr<Expr> Importer::parseLValue() {
  FailureOr<std::pair<StringRef, SMLoc>> name = expectIdentifier("a variable");
  if (failed(name)) {
    return failure();
  }
  auto it = scope.find(name->first);
  if (it == scope.end()) {
    return emitError(name->second) << "unknown variable '" << name->first << "'";
  }
  if (it->second.kind != Binding::Kind::Variable) {
    return emitError(name->second) << "cannot assign to the qubit '" << name->first << "'";
  }
  Value ref = it->second.value;
  if (!token().is(TokenKind::LBracket)) {
    return Expr{.value = ref, .loc = name->second};
  }
  auto bits = dyn_cast<BitsType>(cast<RefType>(ref.getType()).getElementType());
  if (!bits) {
    return emitError(token().getLoc()) << "'" << name->first << "' is a single bit and cannot be indexed";
  }
  FailureOr<Expr> index = parseIndex(name->first, bits.getSize());
  if (failed(index)) {
    return failure();
  }
  auto subref = SubrefOp::create(builder, getLoc(name->second), RefType::get(BitType::get(context)), ref, index->value);
  return Expr{.value = subref, .loc = name->second};
}

//===----------------------------------------------------------------------===//
// Entry points
//===----------------------------------------------------------------------===//

OwningOpRef<ModuleOp> qcc::oq3::importOpenQASM(llvm::SourceMgr& sourceMgr, MLIRContext* context,
                                               const ImportOptions& options) {
  context->loadDialect<OQ3Dialect, QccDialect, func::FuncDialect>();
  return Importer(sourceMgr, context, options).run();
}

void qcc::oq3::registerImportOpenQASMTranslation() {
  static llvm::cl::list<std::string> includeDirs("I", llvm::cl::desc("Directory to search for OpenQASM include files"),
                                                 llvm::cl::value_desc("directory"), llvm::cl::Prefix);
  static llvm::cl::opt<bool> allowDevVersion(
      "oq3-allow-dev-version",
      llvm::cl::desc("Import programs of the unreleased OpenQASM version 3.2, the development specification"),
      llvm::cl::init(false));

  static const TranslateToMLIRRegistration registration(
      "import-openqasm", "Import OpenQASM 3 into the oq3 dialect",
      [](const std::shared_ptr<llvm::SourceMgr>& sourceMgr, MLIRContext* context) -> OwningOpRef<Operation*> {
        ImportOptions options;
        options.includeDirs.assign(includeDirs.begin(), includeDirs.end());
        options.allowDevVersion = allowDevVersion;
        return importOpenQASM(*sourceMgr, context, options);
      },
      [](DialectRegistry& registry) { registry.insert<OQ3Dialect, QccDialect, func::FuncDialect>(); });
}
