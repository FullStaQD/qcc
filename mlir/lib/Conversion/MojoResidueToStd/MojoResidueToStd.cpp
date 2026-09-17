// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// Translates elaborated Mojo IR into the dialects the PrelimHLEP pipeline
// consumes.
//
// The input is the generic-form output of `kgen -elaborate`, parsed with
// unregistered dialects allowed and with parse-time verification disabled.
// Everything Mojo emits is therefore an unregistered op here, except the
// `prelimhlep` ops the eDSL library built through `__mlir_op`: Mojo registers
// the dialect from qcc's own TableGen, so those arrive fully formed, operand
// segments and all.
//
// The pass rebuilds each `kgen.func` as a `func.func` rather than rewriting
// in place: block argument types change (`!kgen.scalar<bool>` becomes `i1`),
// Mojo's structs are taken apart into the values they hold, and the
// `kgen`/`hlcf`/`pop` ops have no interfaces qcc could drive. The translation
// is total on a closed table and fails loudly, at the op's Mojo source
// location, on everything else.
//
//===----------------------------------------------------------------------===//

#include "qcc/Conversion/MojoResidueToStd/MojoResidueToStd.h"

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include "mlir/AsmParser/AsmParser.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/Support/raw_ostream.h"

#include <optional>
#include <string>

namespace qcc {
using namespace mlir;
namespace hlep = qcc::prelimhlep;

#define GEN_PASS_DEF_MOJORESIDUETOSTD
#include "qcc/Conversion/MojoResidueToStd/MojoResidueToStd.h.inc"

namespace {

constexpr llvm::StringLiteral kHaloAttrName = "prelimhlep.halo";
constexpr llvm::StringLiteral kSymNameAttrName = "sym_name";
constexpr llvm::StringLiteral kIndexAttrName = "index";
constexpr llvm::StringLiteral kValueAttrName = "value";

/// A Mojo scalar type after translation: the MLIR type qcc uses for it, plus
/// the signedness that the Mojo dtype carried and the builtin type does not.
/// Ops that need signedness (`cmp`, `shr`, `div`, `rem`, widening casts) read
/// it off their *operand* types, which is where Mojo keeps it.
struct Scalar {
  Type type;
  bool isSigned = false;
};

/// The `!kgen.scalar<dtype>` element type for `dtype`, or nullopt if the
/// dtype is not one a quantum kernel can use.
std::optional<Scalar> translateDType(llvm::StringRef dtype, MLIRContext* context) {
  if (dtype == "bool") {
    return Scalar{IntegerType::get(context, 1), false};
  }
  if (dtype == "index") {
    return Scalar{IndexType::get(context), true};
  }
  if (dtype == "f16") {
    return Scalar{Float16Type::get(context), true};
  }
  if (dtype == "f32") {
    return Scalar{Float32Type::get(context), true};
  }
  if (dtype == "f64") {
    return Scalar{Float64Type::get(context), true};
  }
  const bool isSigned = dtype.consume_front("si");
  if (!isSigned && !dtype.consume_front("ui")) {
    return std::nullopt;
  }
  unsigned width = 0;
  if (dtype.getAsInteger(10, width) || width == 0) {
    return std::nullopt;
  }
  return Scalar{IntegerType::get(context, width), isSigned};
}

/// Translate a Mojo type. Builtin types (which Mojo produces through
/// `pop.cast_to_builtin`, and which the eDSL library writes directly for the
/// complex factor `prelimhlep.scale` takes) and `prelimhlep` types pass
/// through unchanged; `!kgen.scalar<dtype>` becomes the corresponding builtin
/// type. Everything else is outside the kernel vocabulary.
std::optional<Scalar> translateType(Type type) {
  if (isa<IntegerType, IndexType, FloatType, ComplexType>(type)) {
    // Builtin integers are signless, so nothing here can be "signed"; the
    // library keeps signedness on the Mojo side of a `cast_to_builtin`.
    return Scalar{type, isa<IndexType>(type)};
  }
  if (isa<hlep::LinType, hlep::UnitType>(type)) {
    return Scalar{type, false};
  }
  auto opaque = dyn_cast<OpaqueType>(type);
  if (!opaque || opaque.getDialectNamespace() != "kgen") {
    return std::nullopt;
  }
  llvm::StringRef data = opaque.getTypeData();
  if (!data.consume_front("scalar<") || !data.consume_back(">")) {
    return std::nullopt;
  }
  return translateDType(data, type.getContext());
}

/// Mojo keeps an op's inherent attributes in properties, which reach an
/// unregistered op as one dictionary rather than as attributes.
Attribute lookupAttr(Operation* op, llvm::StringRef name) {
  if (Attribute attr = op->getAttr(name)) {
    return attr;
  }
  if (auto properties = dyn_cast_or_null<DictionaryAttr>(op->getPropertiesAsAttribute())) {
    return properties.get(name);
  }
  return {};
}

/// The keyword of a Mojo parametric attribute printed as `#kgen<KIND WORD>`:
/// with `kind` of `cmp_pred`, `#kgen<cmp_pred lt>` gives `lt`. Such an
/// attribute belongs to a dialect qcc does not have, so it arrives
/// uninterpreted and its print is the only thing there is to read. The shape
/// is matched exactly rather than scanned for a trailing word, so that an
/// attribute of some other Mojo kind is a miss rather than a misreading.
std::optional<std::string> kgenKeyword(Attribute attr, llvm::StringRef kind) {
  if (!attr) {
    return std::nullopt;
  }
  std::string printed;
  llvm::raw_string_ostream stream(printed);
  attr.print(stream);
  llvm::StringRef text(printed);
  if (!text.consume_front("#kgen<") || !text.consume_front(kind) || !text.consume_front(" ")) {
    return std::nullopt;
  }
  const size_t end = text.find('>');
  if (end == llvm::StringRef::npos) {
    return std::nullopt;
  }
  return text.take_front(end).str();
}

/// The field types of a Mojo struct type, or nullopt if `type` is not one.
///
/// `!kgen.struct<(A, B)>` reaches qcc as an opaque type carrying its fields as
/// text, so they are parsed back out. A nested struct prints without the
/// dialect prefix (`struct<(...)>`), which goes back on before parsing.
std::optional<SmallVector<Type>> getStructFields(Type type) {
  auto opaque = dyn_cast<OpaqueType>(type);
  if (!opaque || opaque.getDialectNamespace() != "kgen") {
    return std::nullopt;
  }
  llvm::StringRef data = opaque.getTypeData();
  if (!data.consume_front("struct<(") || !data.consume_back(")>")) {
    return std::nullopt;
  }

  SmallVector<Type> fields;
  unsigned depth = 0;
  size_t start = 0;
  for (size_t i = 0; i <= data.size(); ++i) {
    if (i < data.size()) {
      const char c = data[i];
      if (c == '<' || c == '(' || c == '{' || c == '[') {
        ++depth;
        continue;
      }
      if (c == '>' || c == ')' || c == '}' || c == ']') {
        --depth;
        continue;
      }
      if (c != ',' || depth != 0) {
        continue;
      }
    }
    llvm::StringRef field = data.slice(start, i).trim();
    start = i + 1;
    if (field.empty()) {
      // `!kgen.struct<()>` holds nothing, and so translates to nothing.
      continue;
    }
    const std::string text = field.starts_with("!") ? field.str() : ("!kgen." + field).str();
    Type parsed = mlir::parseType(text, type.getContext());
    if (!parsed) {
      return std::nullopt;
    }
    fields.push_back(parsed);
  }
  return fields;
}

/// The qcc types a Mojo value of `type` translates to: one for a scalar or a
/// `prelimhlep` value, and the leaves of its fields in order for a struct,
/// which qcc's kernel vocabulary has nothing to hold. Nullopt means some leaf
/// is outside that vocabulary.
std::optional<SmallVector<Type>> flattenType(Type type) {
  if (std::optional<SmallVector<Type>> fields = getStructFields(type)) {
    SmallVector<Type> leaves;
    for (Type field : *fields) {
      std::optional<SmallVector<Type>> nested = flattenType(field);
      if (!nested) {
        return std::nullopt;
      }
      llvm::append_range(leaves, *nested);
    }
    return leaves;
  }
  if (std::optional<Scalar> scalar = translateType(type)) {
    return SmallVector<Type>{scalar->type};
  }
  return std::nullopt;
}

/// The symbol a Mojo callee attribute names. Mojo writes `#kgen.symbol<@name>`
/// for a call and `#kgen.symbol.constant<@name> : <type>` for a function value
/// it has already resolved; qcc has no attribute for either, so the name is
/// read back out of the print. A mangled Mojo name is rarely a bare identifier
/// -- `@"hlep::phase_tag4[def(::SIMD[DType._uint4, 1]) thin -> Bool]"` is one
/// -- so the quoted form is unescaped rather than scanned for a delimiter.
std::optional<std::string> kgenSymbolName(Attribute attr) {
  if (!attr) {
    return std::nullopt;
  }
  std::string printed;
  llvm::raw_string_ostream stream(printed);
  attr.print(stream);
  llvm::StringRef text(printed);
  if (!text.consume_front("#kgen.symbol")) {
    return std::nullopt;
  }
  text.consume_front(".constant");
  if (!text.consume_front("<@")) {
    return std::nullopt;
  }
  if (!text.consume_front("\"")) {
    llvm::StringRef bare = text.take_until([](char c) { return c == '>'; });
    return bare.empty() ? std::nullopt : std::optional<std::string>(bare.str());
  }

  std::string name;
  for (size_t i = 0; i < text.size(); ++i) {
    if (text[i] == '"') {
      return name;
    }
    if (text[i] == '\\' && i + 1 < text.size()) {
      ++i;
    }
    name.push_back(text[i]);
  }
  return std::nullopt;
}

/// The `arith.cmpi` predicate for a Mojo `pop.cmp` predicate keyword.
std::optional<arith::CmpIPredicate> translateCmpPredicate(llvm::StringRef pred, bool isSigned) {
  if (pred == "eq") {
    return arith::CmpIPredicate::eq;
  }
  if (pred == "ne") {
    return arith::CmpIPredicate::ne;
  }
  if (pred == "lt") {
    return isSigned ? arith::CmpIPredicate::slt : arith::CmpIPredicate::ult;
  }
  if (pred == "le") {
    return isSigned ? arith::CmpIPredicate::sle : arith::CmpIPredicate::ule;
  }
  if (pred == "gt") {
    return isSigned ? arith::CmpIPredicate::sgt : arith::CmpIPredicate::ugt;
  }
  if (pred == "ge") {
    return isSigned ? arith::CmpIPredicate::sge : arith::CmpIPredicate::uge;
  }
  return std::nullopt;
}

/// Translator state: one per module, carrying the value mapping across the
/// recursive descent into regions.
class Translator {
public:
  explicit Translator(ModuleOp module) : module(module) {}

  LogicalResult run();

private:
  /// Translate `op` and map its results. `builder` is positioned where the
  /// replacement goes.
  LogicalResult translateOp(Operation* op, OpBuilder& builder);

  /// Translate every op of `source` into `target`, whose arguments must
  /// already be mapped.
  LogicalResult translateBlock(Block& source, Block& target);

  /// Translated operands of `op`, in order and with each struct operand
  /// contributing the values it was taken apart into, or failure if one was
  /// never mapped.
  LogicalResult getOperands(Operation* op, SmallVectorImpl<Value>& result);

  /// Translated result types of `op`, one per result, or failure on an
  /// untranslatable type. For an op that may produce a struct, use
  /// `getFlatResultTypes` instead.
  LogicalResult getResultTypes(Operation* op, SmallVectorImpl<Type>& result);

  /// Translated result types of `op` with struct results taken apart, along
  /// with the number of types each result contributed.
  LogicalResult getFlatResultTypes(Operation* op, SmallVectorImpl<Type>& types, SmallVectorImpl<unsigned>& counts);

  /// Translated types of `block`'s arguments, taken apart the same way, with
  /// one location per translated type and the per-argument counts.
  LogicalResult getFlatArgumentTypes(Block& block, SmallVectorImpl<Type>& types, SmallVectorImpl<Location>& locs,
                                     SmallVectorImpl<unsigned>& counts);

  /// Map `op`'s results onto `replacement`'s, one for one.
  void mapResults(Operation* op, Operation* replacement);

  /// Map `op`'s results onto `values`, giving each result as many of them as
  /// `counts` says it takes.
  void mapFlatResults(Operation* op, ValueRange values, ArrayRef<unsigned> counts);

  /// Map `source`'s block arguments onto `target`'s, per `counts`.
  void mapBlockArguments(Block& source, Block& target, ArrayRef<unsigned> counts);

  /// Record what `original` translates to. A scalar or a `prelimhlep` value
  /// takes one value, a struct takes the values of its leaves.
  void map(Value original, ValueRange translated);

  /// Per-op-name handlers. Each may assume operands and result types have
  /// already been translated.
  LogicalResult translateFunc(Operation* op);
  LogicalResult translateIf(Operation* op, OpBuilder& builder);
  LogicalResult translateBinary(Operation* op, OpBuilder& builder, llvm::StringRef mnemonic);
  LogicalResult translateCmp(Operation* op, OpBuilder& builder);
  LogicalResult translateCast(Operation* op, OpBuilder& builder);
  LogicalResult translateCall(Operation* op, OpBuilder& builder);
  LogicalResult translateConstant(Operation* op, OpBuilder& builder);
  LogicalResult translateStructCreate(Operation* op);
  LogicalResult translateStructExtract(Operation* op);
  LogicalResult translatePrelimHLEP(Operation* op, OpBuilder& builder);

  /// Forward `op`'s single operand to its single result without emitting
  /// anything: the casts between a Mojo scalar and its builtin type.
  LogicalResult forward(Operation* op);

  /// Signedness of `op`'s first operand, as Mojo recorded it.
  bool isOperandSigned(Operation* op);

  /// Remove the module attributes Mojo stamps its build environment into,
  /// which belong to dialects qcc does not have.
  void dropForeignModuleAttrs();

  /// Tag every translated function that is quantum, or that calls one, with
  /// `prelimhlep.halo`.
  void tagHaloFunctions();

  /// Give every haloed function that takes no arguments a leading
  /// `!prelimhlep.unit` argument, and pass a unit value at every call to one.
  void addUnitArguments(const DenseSet<StringRef>& halo);

  ModuleOp module;

  /// What each Mojo value translates to. Mojo's struct has no counterpart in
  /// qcc's kernel vocabulary, so a struct value is held as the list of values
  /// its leaves translated to; everything else is one value.
  DenseMap<Value, SmallVector<Value, 1>> mapping;
};

void Translator::map(Value original, ValueRange translated) {
  // Copied before the insert, because `translated` may alias the entry that
  // `mapping[original]` is about to overwrite or move.
  SmallVector<Value, 1> values(translated.begin(), translated.end());
  mapping[original] = std::move(values);
}

bool Translator::isOperandSigned(Operation* op) {
  if (op->getNumOperands() == 0) {
    return false;
  }
  std::optional<Scalar> scalar = translateType(op->getOperand(0).getType());
  return scalar && scalar->isSigned;
}

LogicalResult Translator::getOperands(Operation* op, SmallVectorImpl<Value>& result) {
  for (Value operand : op->getOperands()) {
    auto mapped = mapping.find(operand);
    if (mapped == mapping.end()) {
      return op->emitError("operand has no translation; it is defined by an "
                           "operation this pass skipped");
    }
    // An empty struct translates to no values at all, which is why the
    // presence of the entry rather than its size is what is checked.
    llvm::append_range(result, mapped->second);
  }
  return success();
}

LogicalResult Translator::getResultTypes(Operation* op, SmallVectorImpl<Type>& result) {
  for (Type type : op->getResultTypes()) {
    std::optional<Scalar> scalar = translateType(type);
    if (!scalar) {
      return op->emitError("type ") << type << " is not supported in a quantum kernel";
    }
    result.push_back(scalar->type);
  }
  return success();
}

LogicalResult Translator::getFlatResultTypes(Operation* op, SmallVectorImpl<Type>& types,
                                             SmallVectorImpl<unsigned>& counts) {
  for (Type type : op->getResultTypes()) {
    std::optional<SmallVector<Type>> leaves = flattenType(type);
    if (!leaves) {
      return op->emitError("type ") << type << " is not supported in a quantum kernel";
    }
    counts.push_back(leaves->size());
    llvm::append_range(types, *leaves);
  }
  return success();
}

LogicalResult Translator::getFlatArgumentTypes(Block& block, SmallVectorImpl<Type>& types,
                                               SmallVectorImpl<Location>& locs, SmallVectorImpl<unsigned>& counts) {
  for (BlockArgument arg : block.getArguments()) {
    std::optional<SmallVector<Type>> leaves = flattenType(arg.getType());
    if (!leaves) {
      return mlir::emitError(arg.getLoc(), "argument type ")
             << arg.getType() << " is not supported in a quantum kernel";
    }
    counts.push_back(leaves->size());
    llvm::append_range(types, *leaves);
    locs.append(leaves->size(), arg.getLoc());
  }
  return success();
}

void Translator::mapResults(Operation* op, Operation* replacement) {
  for (auto [original, translated] : llvm::zip_equal(op->getResults(), replacement->getResults())) {
    map(original, translated);
  }
}

void Translator::mapFlatResults(Operation* op, ValueRange values, ArrayRef<unsigned> counts) {
  unsigned offset = 0;
  for (auto [result, count] : llvm::zip_equal(op->getResults(), counts)) {
    map(result, values.slice(offset, count));
    offset += count;
  }
}

void Translator::mapBlockArguments(Block& source, Block& target, ArrayRef<unsigned> counts) {
  unsigned offset = 0;
  for (auto [arg, count] : llvm::zip_equal(source.getArguments(), counts)) {
    map(arg, target.getArguments().slice(offset, count));
    offset += count;
  }
}

LogicalResult Translator::forward(Operation* op) {
  if (op->getNumOperands() != 1 || op->getNumResults() != 1) {
    return op->emitError("expected exactly one operand and one result");
  }
  auto mapped = mapping.find(op->getOperand(0));
  if (mapped == mapping.end()) {
    return op->emitError("operand has no translation");
  }
  map(op->getResult(0), ValueRange(ArrayRef<Value>(mapped->second)));
  return success();
}

LogicalResult Translator::translateBlock(Block& source, Block& target) {
  OpBuilder builder = OpBuilder::atBlockEnd(&target);
  for (Operation& op : source) {
    if (failed(translateOp(&op, builder))) {
      return failure();
    }
  }
  return success();
}

LogicalResult Translator::translateBinary(Operation* op, OpBuilder& builder, llvm::StringRef mnemonic) {
  // `arith` splits by signedness what Mojo's dtype already decided. The name
  // is resolved before anything else so that an op outside the table is
  // reported as such, rather than through its operand types.
  const bool isSigned = isOperandSigned(op);
  const std::string name = llvm::StringSwitch<std::string>(mnemonic)
                               .Case("add", "arith.addi")
                               .Case("sub", "arith.subi")
                               .Case("mul", "arith.muli")
                               .Case("shl", "arith.shli")
                               .Case("simd.and", "arith.andi")
                               .Case("simd.or", "arith.ori")
                               .Case("simd.xor", "arith.xori")
                               .Case("shr", isSigned ? "arith.shrsi" : "arith.shrui")
                               .Case("div", isSigned ? "arith.divsi" : "arith.divui")
                               .Case("rem", isSigned ? "arith.remsi" : "arith.remui")
                               .Default("");
  if (name.empty()) {
    return op->emitError("'") << op->getName() << "' is not supported in a quantum kernel";
  }

  SmallVector<Value> operands;
  SmallVector<Type> resultTypes;
  if (failed(getOperands(op, operands)) || failed(getResultTypes(op, resultTypes))) {
    return failure();
  }
  if (operands.size() != 2 || resultTypes.size() != 1) {
    return op->emitError("expected two operands and one result");
  }
  if (!isa<IntegerType, IndexType>(resultTypes.front())) {
    return op->emitError("only integer arithmetic is supported in a quantum "
                         "kernel, got ")
           << resultTypes.front();
  }

  OperationState state(op->getLoc(), name, operands, resultTypes, {});
  Operation* replacement = builder.create(state);
  mapResults(op, replacement);
  return success();
}

LogicalResult Translator::translateCmp(Operation* op, OpBuilder& builder) {
  SmallVector<Value> operands;
  if (failed(getOperands(op, operands))) {
    return failure();
  }
  if (operands.size() != 2 || op->getNumResults() != 1) {
    return op->emitError("expected two operands and one result");
  }
  auto pred = op->getAttrOfType<Attribute>("pred");
  if (!pred) {
    return op->emitError("'pop.cmp' without a 'pred' attribute");
  }

  // Mojo writes the predicate as its own `#kgen<cmp_pred lt>`, which qcc can
  // only read back out of the print.
  std::string keyword;
  if (std::optional<std::string> word = kgenKeyword(pred, "cmp_pred")) {
    keyword = *word;
  } else if (auto str = dyn_cast<StringAttr>(pred)) {
    keyword = str.getValue().str();
  }
  std::optional<arith::CmpIPredicate> predicate = translateCmpPredicate(keyword, isOperandSigned(op));
  if (!predicate) {
    return op->emitError("comparison predicate ") << pred << " is not supported in a quantum kernel";
  }
  if (!isa<IntegerType, IndexType>(operands.front().getType())) {
    return op->emitError("only integer comparisons are supported in a quantum "
                         "kernel");
  }

  auto replacement = arith::CmpIOp::create(builder, op->getLoc(), *predicate, operands[0], operands[1]);
  mapResults(op, replacement);
  return success();
}

LogicalResult Translator::translateCast(Operation* op, OpBuilder& builder) {
  SmallVector<Value> operands;
  SmallVector<Type> resultTypes;
  if (failed(getOperands(op, operands)) || failed(getResultTypes(op, resultTypes))) {
    return failure();
  }
  if (operands.size() != 1 || resultTypes.size() != 1) {
    return op->emitError("expected one operand and one result");
  }
  auto from = dyn_cast<IntegerType>(operands.front().getType());
  auto to = dyn_cast<IntegerType>(resultTypes.front());
  if (!from || !to) {
    return op->emitError("only integer casts are supported in a quantum "
                         "kernel");
  }
  if (from == to) {
    map(op->getResult(0), operands.front());
    return success();
  }

  Value result;
  if (from.getWidth() > to.getWidth()) {
    result = arith::TruncIOp::create(builder, op->getLoc(), to, operands[0]);
  } else if (isOperandSigned(op)) {
    result = arith::ExtSIOp::create(builder, op->getLoc(), to, operands[0]);
  } else {
    result = arith::ExtUIOp::create(builder, op->getLoc(), to, operands[0]);
  }
  map(op->getResult(0), result);
  return success();
}

/// The integer a `kgen.param.constant` holds. Mojo writes a builtin attribute
/// for a value it has already lowered to one and its own `#kgen<simd N>` for
/// one still carrying a Mojo dtype; both reach a kernel, so both are read.
std::optional<int64_t> constantValue(Attribute value) {
  if (auto boolean = dyn_cast_or_null<BoolAttr>(value)) {
    return boolean.getValue() ? 1 : 0;
  }
  if (auto integer = dyn_cast_or_null<IntegerAttr>(value)) {
    return integer.getValue().getSExtValue();
  }
  std::optional<std::string> word = kgenKeyword(value, "simd");
  if (!word) {
    return std::nullopt;
  }
  if (*word == "true") {
    return 1;
  }
  if (*word == "false") {
    return 0;
  }
  int64_t number = 0;
  if (llvm::StringRef(*word).getAsInteger(10, number)) {
    return std::nullopt;
  }
  return number;
}

LogicalResult Translator::translateConstant(Operation* op, OpBuilder& builder) {
  SmallVector<Type> resultTypes;
  if (failed(getResultTypes(op, resultTypes))) {
    return failure();
  }
  if (resultTypes.size() != 1) {
    return op->emitError("expected one result");
  }
  if (!isa<IntegerType, IndexType>(resultTypes.front())) {
    return op->emitError("only integer constants are supported in a quantum "
                         "kernel, got ")
           << resultTypes.front();
  }
  std::optional<int64_t> value = constantValue(lookupAttr(op, kValueAttrName));
  if (!value) {
    return op->emitError("only integer constants are supported in a quantum "
                         "kernel");
  }
  auto replacement = arith::ConstantOp::create(builder, op->getLoc(), IntegerAttr::get(resultTypes.front(), *value));
  mapResults(op, replacement);
  return success();
}

LogicalResult Translator::translateStructCreate(Operation* op) {
  // A struct is only ever a way to carry several values at once; qcc keeps the
  // values and drops the wrapper, so building one costs nothing here.
  if (op->getNumResults() != 1) {
    return op->emitError("expected one result");
  }
  SmallVector<Value> operands;
  if (failed(getOperands(op, operands))) {
    return failure();
  }
  map(op->getResult(0), operands);
  return success();
}

LogicalResult Translator::translateStructExtract(Operation* op) {
  if (op->getNumOperands() != 1 || op->getNumResults() != 1) {
    return op->emitError("expected one operand and one result");
  }
  Value container = op->getOperand(0);
  auto mapped = mapping.find(container);
  if (mapped == mapping.end()) {
    return op->emitError("operand has no translation");
  }
  auto index = dyn_cast_or_null<IntegerAttr>(lookupAttr(op, kIndexAttrName));
  if (!index) {
    return op->emitError("'") << op->getName()
                              << "' with a parametric index is not supported in a quantum "
                                 "kernel; the elaborator resolves one at a concrete call site";
  }
  std::optional<SmallVector<Type>> fields = getStructFields(container.getType());
  if (!fields) {
    return op->emitError("'") << op->getName() << "' from " << container.getType()
                              << ", which is not a struct this pass can take apart";
  }
  const int64_t field = index.getValue().getSExtValue();
  if (field < 0 || field >= static_cast<int64_t>(fields->size())) {
    return op->emitError("field index ") << field << " is out of range for " << container.getType();
  }

  // The values of the fields before this one are what it is offset by.
  unsigned offset = 0;
  for (int64_t i = 0; i < field; ++i) {
    std::optional<SmallVector<Type>> leaves = flattenType((*fields)[i]);
    if (!leaves) {
      return op->emitError("field type ") << (*fields)[i] << " is not supported in a quantum kernel";
    }
    offset += leaves->size();
  }
  std::optional<SmallVector<Type>> leaves = flattenType((*fields)[field]);
  if (!leaves) {
    return op->emitError("field type ") << (*fields)[field] << " is not supported in a quantum kernel";
  }
  if (offset + leaves->size() > mapped->second.size()) {
    return op->emitError("struct value holds fewer translated values than its "
                         "type calls for");
  }
  SmallVector<Value> extracted(ArrayRef<Value>(mapped->second).slice(offset, leaves->size()));
  map(op->getResult(0), extracted);
  return success();
}

LogicalResult Translator::translateCall(Operation* op, OpBuilder& builder) {
  SmallVector<Value> operands;
  SmallVector<Type> resultTypes;
  SmallVector<unsigned> resultCounts;
  if (failed(getOperands(op, operands)) || failed(getFlatResultTypes(op, resultTypes, resultCounts))) {
    return failure();
  }

  Attribute callee = lookupAttr(op, "callee");
  std::string name;
  if (auto flat = dyn_cast_or_null<FlatSymbolRefAttr>(callee)) {
    name = flat.getValue().str();
  } else if (std::optional<std::string> symbol = kgenSymbolName(callee)) {
    name = *symbol;
  }
  if (name.empty()) {
    return op->emitError("could not determine the callee of '") << op->getName() << "'";
  }

  auto replacement = func::CallOp::create(builder, op->getLoc(), name, resultTypes, operands);
  mapFlatResults(op, replacement.getResults(), resultCounts);
  return success();
}

LogicalResult Translator::translateIf(Operation* op, OpBuilder& builder) {
  SmallVector<Value> operands;
  SmallVector<Type> resultTypes;
  SmallVector<unsigned> resultCounts;
  if (failed(getOperands(op, operands)) || failed(getFlatResultTypes(op, resultTypes, resultCounts))) {
    return failure();
  }
  if (operands.size() != 1 || op->getNumRegions() != 2) {
    return op->emitError("expected one condition and two regions");
  }
  if (!operands.front().getType().isInteger(1)) {
    return op->emitError("'hlcf.if' condition must be a boolean");
  }

  auto replacement = scf::IfOp::create(builder, op->getLoc(), resultTypes, operands.front(), /*withElseRegion=*/true);
  for (auto [source, target] : llvm::zip_equal(op->getRegions(), replacement->getRegions())) {
    if (!source.hasOneBlock()) {
      return op->emitError("'hlcf.if' region must have exactly one block");
    }
    if (target.empty()) {
      target.emplaceBlock();
    }
    Block& targetBlock = target.front();
    // A result-less `scf.if` starts out with an implicit `scf.yield`; the
    // translated `hlcf.yield` takes its place.
    if (!targetBlock.empty()) {
      targetBlock.front().erase();
    }
    if (failed(translateBlock(source.front(), targetBlock))) {
      return failure();
    }
  }
  mapFlatResults(op, replacement.getResults(), resultCounts);
  return success();
}

LogicalResult Translator::translatePrelimHLEP(Operation* op, OpBuilder& builder) {
  // A `prelimhlep.lin` with several results comes back from Mojo as one
  // struct, because inline MLIR gives a Mojo expression a single value; the
  // op qcc wants has the results themselves.
  SmallVector<Value> operands;
  SmallVector<Type> resultTypes;
  SmallVector<unsigned> resultCounts;
  if (failed(getOperands(op, operands)) || failed(getFlatResultTypes(op, resultTypes, resultCounts))) {
    return failure();
  }

  // A `prelimhlep` op is already the op qcc wants; only its operands and the
  // types inside its regions change. The properties come over wholesale, so
  // `prelimhlep.output` keeps the operand segments Mojo wrote for it.
  OperationState state(op->getLoc(), op->getName().getStringRef(), operands, resultTypes, op->getAttrs(), {},
                       /*regions=*/{});
  for (unsigned i = 0, e = op->getNumRegions(); i < e; ++i) {
    state.addRegion();
  }
  Operation* replacement = builder.create(state);
  if (Attribute properties = op->getPropertiesAsAttribute()) {
    if (failed(replacement->setPropertiesFromAttribute(properties, [&] { return op->emitError(); }))) {
      return failure();
    }
  }

  // `createBlock` below moves the insertion point into the new region; the
  // caller keeps inserting after this op.
  OpBuilder::InsertionGuard guard(builder);
  for (auto [source, target] : llvm::zip_equal(op->getRegions(), replacement->getRegions())) {
    if (source.empty()) {
      continue;
    }
    if (!source.hasOneBlock()) {
      return op->emitError("region must have exactly one block");
    }
    Block& sourceBlock = source.front();
    SmallVector<Type> argTypes;
    SmallVector<Location> argLocs;
    SmallVector<unsigned> argCounts;
    if (failed(getFlatArgumentTypes(sourceBlock, argTypes, argLocs, argCounts))) {
      return failure();
    }
    Block* targetBlock = builder.createBlock(&target, target.end(), argTypes, argLocs);
    mapBlockArguments(sourceBlock, *targetBlock, argCounts);
    if (failed(translateBlock(sourceBlock, *targetBlock))) {
      return failure();
    }
  }
  mapFlatResults(op, replacement->getResults(), resultCounts);
  return success();
}

LogicalResult Translator::translateOp(Operation* op, OpBuilder& builder) {
  const llvm::StringRef dialect = op->getName().getDialectNamespace();
  const llvm::StringRef mnemonic = op->getName().getStringRef().drop_front(dialect.size() + 1);

  if (dialect == hlep::PrelimHLEPDialect::getDialectNamespace()) {
    return translatePrelimHLEP(op, builder);
  }

  // Dialects qcc and Mojo share verbatim: `index` is upstream, and `arith`
  // and `complex` appear when the eDSL library itself writes inline MLIR
  // (constants for `prelimhlep.scale`, for instance).
  if (dialect == "index" || dialect == "arith" || dialect == "complex") {
    if (op->getNumRegions() != 0) {
      return op->emitError("'") << op->getName() << "' with regions is not supported in a quantum kernel";
    }
    SmallVector<Value> operands;
    SmallVector<Type> resultTypes;
    if (failed(getOperands(op, operands)) || failed(getResultTypes(op, resultTypes))) {
      return failure();
    }
    OperationState state(op->getLoc(), op->getName().getStringRef(), operands, resultTypes, op->getAttrs());
    mapResults(op, builder.create(state));
    return success();
  }

  if (dialect == "pop") {
    if (mnemonic == "stack_allocation" || mnemonic == "load" || mnemonic == "store") {
      // Mem2Reg promotes a local away unless its value has to survive a
      // boundary it cannot carry one across. Inside a kernel the only such
      // boundary is a linearization body, so a memory op that gets this far
      // is a variable written in a body and read after it.
      return op->emitError("'") << op->getName()
                                << "' is not supported in a quantum kernel: a value assigned "
                                   "inside a linearization body cannot be read after it; results "
                                   "leave a body through 'prelimhlep.output'";
    }
    if (mnemonic == "cast_to_builtin" || mnemonic == "cast_from_builtin") {
      return forward(op);
    }
    if (mnemonic == "cast") {
      return translateCast(op, builder);
    }
    if (mnemonic == "cmp") {
      return translateCmp(op, builder);
    }
    if (mnemonic == "select") {
      SmallVector<Value> operands;
      if (failed(getOperands(op, operands))) {
        return failure();
      }
      if (operands.size() != 3) {
        return op->emitError("expected three operands");
      }
      auto replacement = arith::SelectOp::create(builder, op->getLoc(), operands[0], operands[1], operands[2]);
      mapResults(op, replacement);
      return success();
    }
    return translateBinary(op, builder, mnemonic);
  }

  if (dialect == "hlcf") {
    if (mnemonic == "if") {
      return translateIf(op, builder);
    }
    if (mnemonic == "yield") {
      SmallVector<Value> operands;
      if (failed(getOperands(op, operands))) {
        return failure();
      }
      scf::YieldOp::create(builder, op->getLoc(), operands);
      return success();
    }
  }

  if (dialect == "kgen") {
    if (mnemonic == "return") {
      SmallVector<Value> operands;
      if (failed(getOperands(op, operands))) {
        return failure();
      }
      func::ReturnOp::create(builder, op->getLoc(), operands);
      return success();
    }
    if (mnemonic == "call") {
      return translateCall(op, builder);
    }
    if (mnemonic == "param.constant") {
      return translateConstant(op, builder);
    }
    if (mnemonic == "struct.create") {
      return translateStructCreate(op);
    }
    if (mnemonic == "struct.extract") {
      return translateStructExtract(op);
    }
  }

  return op->emitError("'") << op->getName() << "' is not supported in a quantum kernel";
}

/// Whether a `kgen.func` is an entry point. Mojo's `@export("name")` sets
/// `exportKind` to `exported`; everything else is an implementation detail of
/// the kernel and becomes a private symbol, so that the inliner may flatten it
/// and symbol DCE may drop it.
bool isExported(Operation* op) {
  Attribute exportKind = lookupAttr(op, "exportKind");
  if (!exportKind) {
    return false;
  }
  if (auto integer = dyn_cast<IntegerAttr>(exportKind)) {
    return !integer.getValue().isZero();
  }
  std::string printed;
  llvm::raw_string_ostream stream(printed);
  exportKind.print(stream);
  return llvm::StringRef(printed).contains("exported") && !llvm::StringRef(printed).contains("not_exported");
}

LogicalResult Translator::translateFunc(Operation* op) {
  auto symName = dyn_cast_or_null<StringAttr>(lookupAttr(op, kSymNameAttrName));
  if (!symName) {
    return op->emitError("'kgen.func' without a 'sym_name'");
  }
  if (op->getNumRegions() != 1 || op->getRegion(0).empty()) {
    return op->emitError("'kgen.func' without a body is not supported in a "
                         "quantum kernel");
  }
  Region& body = op->getRegion(0);
  if (!body.hasOneBlock()) {
    return op->emitError("'kgen.func' body must have exactly one block");
  }
  Block& sourceBlock = body.front();

  // The signature is read off the body rather than off `funcTypeGenerator`,
  // whose `!kgen.generator<...>` type qcc cannot interpret. Mojo returns
  // several values as one struct, which is taken apart here, so the result
  // types are what the translated terminator ends up with rather than what
  // the Mojo one carries.
  SmallVector<Type> argTypes;
  SmallVector<Location> argLocs;
  SmallVector<unsigned> argCounts;
  if (failed(getFlatArgumentTypes(sourceBlock, argTypes, argLocs, argCounts))) {
    return failure();
  }
  Operation* terminator = sourceBlock.getTerminator();
  SmallVector<Type> resultTypes;
  for (Type type : terminator->getOperandTypes()) {
    std::optional<SmallVector<Type>> leaves = flattenType(type);
    if (!leaves) {
      return terminator->emitError("result type ") << type << " is not supported in a quantum kernel";
    }
    llvm::append_range(resultTypes, *leaves);
  }

  OpBuilder builder(op);
  auto func =
      func::FuncOp::create(builder, op->getLoc(), symName.getValue(), builder.getFunctionType(argTypes, resultTypes));
  if (!isExported(op)) {
    func.setPrivate();
  }

  Block* targetBlock = func.addEntryBlock();
  mapBlockArguments(sourceBlock, *targetBlock, argCounts);
  return translateBlock(sourceBlock, *targetBlock);
}

LogicalResult Translator::run() {
  SmallVector<Operation*> functions;
  for (Operation& op : module.getBody()->getOperations()) {
    if (op.getName().getStringRef() == "kgen.func") {
      functions.push_back(&op);
      continue;
    }
    if (isa<func::FuncOp>(op)) {
      continue;
    }
    return op.emitError("'") << op.getName()
                             << "' is not supported at the top level of a quantum kernel "
                                "module";
  }

  for (Operation* function : functions) {
    if (failed(translateFunc(function))) {
      return failure();
    }
  }
  for (Operation* function : functions) {
    function->erase();
  }
  dropForeignModuleAttrs();
  tagHaloFunctions();
  return success();
}

void Translator::dropForeignModuleAttrs() {
  // Mojo stamps every module it emits with its build environment --
  // `M.target_info`, `kgen.env` -- in attributes of dialects qcc does not
  // have. A kernel needs none of it, and leaving it on would mean every later
  // tool in the pipeline had to be run with `--allow-unregistered-dialect`.
  MLIRContext* context = module.getContext();
  SmallVector<StringAttr> foreign;
  for (NamedAttribute attr : module->getDiscardableAttrs()) {
    const llvm::StringRef dialect = attr.getName().strref().split('.').first;
    if (dialect != attr.getName().strref() && !context->getOrLoadDialect(dialect)) {
      foreign.push_back(attr.getName());
    }
  }
  for (StringAttr name : foreign) {
    module->removeDiscardableAttr(name);
  }
}

void Translator::tagHaloFunctions() {
  const auto isQuantumType = [](Type type) { return isa<hlep::PrelimHLEPDialect>(type.getDialect()); };

  // Halo-ness is PrelimHLEP's own definition of quantum-ness, so no Mojo-side
  // decorator is needed. A function is quantum if it mentions a PrelimHLEP
  // type in its signature or builds one in its body -- and then so is every
  // function that calls it, because the inliner refuses to inline a haloed
  // callee into a non-haloed caller, and a kernel entry point's signature is
  // purely classical by the halo rule itself.
  SmallVector<func::FuncOp> worklist;
  DenseSet<StringRef> halo;
  for (auto func : module.getOps<func::FuncOp>()) {
    const bool quantumSignature =
        llvm::any_of(func.getArgumentTypes(), isQuantumType) || llvm::any_of(func.getResultTypes(), isQuantumType);
    const bool quantumBody =
        func.walk([&](Operation* op) {
              return isa<hlep::PrelimHLEPDialect>(op->getDialect()) ? WalkResult::interrupt() : WalkResult::advance();
            })
            .wasInterrupted();
    if (quantumSignature || quantumBody) {
      halo.insert(func.getName());
      worklist.push_back(func);
    }
  }

  bool changed = true;
  while (changed) {
    changed = false;
    for (auto func : module.getOps<func::FuncOp>()) {
      if (halo.contains(func.getName())) {
        continue;
      }
      const bool callsHalo =
          func.walk([&](func::CallOp call) {
                return halo.contains(call.getCallee()) ? WalkResult::interrupt() : WalkResult::advance();
              })
              .wasInterrupted();
      if (callsHalo) {
        halo.insert(func.getName());
        changed = true;
      }
    }
  }

  for (auto func : module.getOps<func::FuncOp>()) {
    if (halo.contains(func.getName())) {
      func->setAttr(kHaloAttrName, hlep::HaloAttr::get(module.getContext()));
    }
  }
  addUnitArguments(halo);
}

void Translator::addUnitArguments(const DenseSet<StringRef>& halo) {
  // A haloed function must take at least one argument, so that the state it
  // acts on is always named (see the halo verifier). Mojo has no way to spell
  // that for a gate that creates a qubit out of nothing, or for an entry
  // point taking no classical arguments, so the importer threads the unit
  // value through instead of asking the user to.
  auto unitType = hlep::UnitType::get(module.getContext());
  DenseSet<StringRef> patched;
  for (auto func : module.getOps<func::FuncOp>()) {
    if (!halo.contains(func.getName()) || func.getNumArguments() != 0 || func.isExternal()) {
      continue;
    }
    func.insertArgument(0, unitType, /*argAttrs=*/{}, func.getLoc());
    patched.insert(func.getName());
  }
  if (patched.empty()) {
    return;
  }

  module.walk([&](func::CallOp call) {
    if (!patched.contains(call.getCallee())) {
      return;
    }
    OpBuilder builder(call);
    auto unit = hlep::UnitValueOp::create(builder, call.getLoc(), unitType);
    SmallVector<Value> operands{unit};
    llvm::append_range(operands, call.getOperands());
    auto replacement = func::CallOp::create(builder, call.getLoc(), call.getCallee(), call.getResultTypes(), operands);
    call.replaceAllUsesWith(replacement.getResults());
    call.erase();
  });
}

struct MojoResidueToStd final : impl::MojoResidueToStdBase<MojoResidueToStd> {
  using MojoResidueToStdBase::MojoResidueToStdBase;

  void runOnOperation() override {
    if (failed(Translator(getOperation()).run())) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
