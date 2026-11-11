// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/QRefToOQ3/QRefToOQ3.h"
#include "qcc/Dialect/OQ3/IR/OQ3.h"
#include "qcc/Dialect/QRef/IR/QRef.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/APFloat.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/Error.h"

#include <cstdint>
#include <optional>
#include <string>

namespace qcc {
#define GEN_PASS_DEF_CONVERTQREFTOOQ3
#include "qcc/Conversion/QRefToOQ3/QRefToOQ3.h.inc"
} // namespace qcc

using namespace mlir;
using namespace qcc;
using namespace qcc::oq3;

/// The spelling of `kind` in `stdgates.inc`, for the gates that have the same name there.
static std::optional<StringRef> getStandardGateName(SingleGateKind kind) {
  switch (kind) {
  case SingleGateKind::X:
  case SingleGateKind::Y:
  case SingleGateKind::Z:
  case SingleGateKind::H:
  case SingleGateKind::S:
  case SingleGateKind::Sdg:
  case SingleGateKind::T:
  case SingleGateKind::Tdg:
  case SingleGateKind::SX:
  case SingleGateKind::RX:
  case SingleGateKind::RY:
  case SingleGateKind::RZ:
    return stringifySingleGateKind(kind);
  default:
    return std::nullopt;
  }
}

/// The spelling of `kind` in `stdgates.inc`, for the gates that have the same name there.
static std::optional<StringRef> getStandardGateName(PairGateKind kind) {
  switch (kind) {
  case PairGateKind::CX:
  case PairGateKind::CY:
  case PairGateKind::CZ:
  case PairGateKind::SWAP:
  case PairGateKind::CP:
    return stringifyPairGateKind(kind);
  default:
    return std::nullopt;
  }
}

/// Whether nothing between `first` and `last`, which follows it in the same block, has a memory effect.
static bool onlyMemoryEffectFreeOpsBetween(Operation* first, Operation* last) {
  for (Operation* op = first->getNextNode(); op != nullptr && op != last; op = op->getNextNode()) {
    if (!isMemoryEffectFree(op)) {
      return false;
    }
  }
  return true;
}

/// Returns the shortest decimal text of the finite `value` that reads back as `value` in its semantics.
static std::string formatFloat(const llvm::APFloat& value) {
  llvm::SmallString<32> text;
  // 36 significant digits identify every value of the widest target `float`, IEEE binary128.
  for (unsigned precision = 1; precision <= 36; ++precision) {
    text.clear();
    value.toString(text, precision);
    llvm::APFloat parsed(value.getSemantics());
    llvm::Expected<llvm::APFloat::opStatus> status = parsed.convertFromString(text, llvm::APFloat::rmNearestTiesToEven);
    if (!status) {
      llvm::consumeError(status.takeError());
      continue;
    }
    if (parsed.bitwiseIsEqual(value)) {
      break;
    }
  }
  // If it happens to be an integer, add a decimal point.
  if (StringRef(text).find_first_of(".eE") == StringRef::npos) {
    text += ".0";
  }
  return text.str().str();
}

namespace {

class Translator {
public:
  /// `floatType` is the target's `float`, the type of the word size.
  Translator(func::FuncOp entry, Type floatType) : entry(entry), floatType(floatType), builder(entry.getContext()) {}

  LogicalResult run();

private:
  LogicalResult translate(Operation* op);
  LogicalResult translateConstant(arith::ConstantOp op);
  LogicalResult translateAlloc(AllocOp op);
  LogicalResult translateAlloca(memref::AllocaOp op);
  LogicalResult translateSubview(memref::SubViewOp op);
  LogicalResult translateStore(memref::StoreOp op);
  LogicalResult translateLoad(memref::LoadOp op);
  LogicalResult translateSingle(qref::SingleOp op);
  LogicalResult translatePair(qref::PairOp op);
  LogicalResult translateMeasure(qref::MeasureOp op);

  /// Returns the `oq3` value of `value`, which an earlier op defined.
  FailureOr<Value> lookup(Value value, Operation* user);
  FailureOr<SmallVector<Value>> lookup(ValueRange values, Operation* user);
  /// Like `lookup`, but `value` must be a float, which is converted to an angle.
  FailureOr<Value> lookupAngle(Value value, Operation* user);

  Value createInt(Location loc, const llvm::APInt& value);
  Value createFloat(Location loc, const llvm::APFloat& value);
  Value createAngle(Location loc, Value floatValue);
  /// Returns the angle `-π/2`.
  Value createNegHalfPi(Location loc);

  void call(Location loc, StringRef gate, ValueRange params, ValueRange qubits);

  std::string freshName(StringRef prefix);

  func::FuncOp entry;
  Type floatType;
  OpBuilder builder;
  llvm::DenseMap<Value, Value> values;
  llvm::DenseMap<Value, Value> storedBits;
  llvm::DenseMap<Value, Operation*> pendingMeasurements;
  unsigned nextNameId = 0;
  bool includeStandardLib = false;
};

} // namespace

LogicalResult Translator::run() {
  Block& body = entry.getBody().front();
  SmallVector<Operation*> translated;
  for (Operation& op : body.without_terminator()) {
    builder.setInsertionPoint(&op);
    if (failed(translate(&op))) {
      return failure();
    }
    translated.push_back(&op);
  }
  for (Operation* op : llvm::reverse(translated)) {
    op->erase();
  }
  if (includeStandardLib) {
    builder.setInsertionPointToStart(&body);
    IncludeOp::create(builder, entry.getLoc(), standardGatesInclude, /*id=*/0);
  }
  return success();
}

std::string Translator::freshName(StringRef prefix) { return (prefix + Twine(nextNameId++)).str(); }

FailureOr<Value> Translator::lookup(Value value, Operation* user) {
  if (Value storage = storedBits.lookup(value)) {
    return RefLoadOp::create(builder, user->getLoc(), storage).getResult();
  }
  if (Value translatedValue = values.lookup(value)) {
    return translatedValue;
  }
  return user->emitError() << "cannot convert an operand of type " << value.getType() << " to OpenQASM";
}

FailureOr<SmallVector<Value>> Translator::lookup(ValueRange values, Operation* user) {
  SmallVector<Value> result;
  for (Value value : values) {
    FailureOr<Value> translatedValue = lookup(value, user);
    if (failed(translatedValue)) {
      return failure();
    }
    result.push_back(*translatedValue);
  }
  return result;
}

FailureOr<Value> Translator::lookupAngle(Value value, Operation* user) {
  FailureOr<Value> translatedValue = lookup(value, user);
  if (failed(translatedValue)) {
    return failure();
  }
  if (!isa<UnsizedFloatType>(translatedValue->getType())) {
    return user->emitError() << "expected a floating-point angle, got " << translatedValue->getType();
  }
  return createAngle(user->getLoc(), *translatedValue);
}

Value Translator::createInt(Location loc, const llvm::APInt& value) {
  MLIRContext* context = builder.getContext();
  if (value.isNegative()) {
    Value magnitude = ConstantOp::create(builder, loc, IntLiteralAttr::get(-value, UnsizedIntType::get(context)));
    return UnaryOp::create(builder, loc, UnaryKind::Neg, magnitude);
  }
  return ConstantOp::create(builder, loc, IntLiteralAttr::get(value, UnsizedIntType::get(context)));
}

Value Translator::createFloat(Location loc, const llvm::APFloat& value) {
  MLIRContext* context = builder.getContext();
  const std::string text = formatFloat(llvm::abs(value));
  Value magnitude =
      ConstantOp::create(builder, loc, FloatLiteralAttr::get(context, text, UnsizedFloatType::get(context)));
  if (value.isNegative()) {
    return UnaryOp::create(builder, loc, UnaryKind::Neg, magnitude);
  }
  return magnitude;
}

Value Translator::createAngle(Location loc, Value floatValue) {
  return CastOp::create(builder, loc, AngleType::get(builder.getContext()), floatValue, /*implicit=*/true);
}

Value Translator::createNegHalfPi(Location loc) {
  MLIRContext* context = builder.getContext();
  Value pi = MathConstantOp::create(builder, loc, UnsizedFloatType::get(context), MathConstantKind::Pi);
  Value two = CastOp::create(builder, loc, UnsizedFloatType::get(context), createInt(loc, llvm::APInt(64, 2)),
                             /*implicit=*/true);
  Value half = BinaryOp::create(builder, loc, pi.getType(), BinaryKind::Div, pi, two);
  return createAngle(loc, UnaryOp::create(builder, loc, UnaryKind::Neg, half));
}

void Translator::call(Location loc, StringRef gate, ValueRange params, ValueRange qubits) {
  if (!lookupBuiltinGate(gate)) {
    includeStandardLib = true;
  }
  GateCallOp::create(builder, loc, gate, params, qubits);
}

//===----------------------------------------------------------------------===//
// Ops
//===----------------------------------------------------------------------===//

LogicalResult Translator::translate(Operation* op) {
  Location loc = op->getLoc();
  MLIRContext* context = builder.getContext();

  // Updates the `values` map to map the result of `op` to a newly created binary operator.
  auto binary = [&](BinaryKind kind) -> LogicalResult {
    FailureOr<SmallVector<Value>> operands = lookup(op->getOperands(), op);
    if (failed(operands)) {
      return failure();
    }
    values[op->getResult(0)] =
        BinaryOp::create(builder, loc, (*operands)[0].getType(), kind, (*operands)[0], (*operands)[1]);
    return success();
  };
  // Updates the `values` map to map the result of `op` to its translated operand. For ops that disappear, such as
  // casts.
  auto forward = [&]() -> LogicalResult {
    FailureOr<Value> operand = lookup(op->getOperand(0), op);
    if (failed(operand)) {
      return failure();
    }
    values[op->getResult(0)] = *operand;
    return success();
  };

  return TypeSwitch<Operation*, LogicalResult>(op)
      .Case([&](arith::ConstantOp constant) { return translateConstant(constant); })
      .Case([&](arith::AddIOp) { return binary(BinaryKind::Add); })
      .Case([&](arith::SubIOp) { return binary(BinaryKind::Sub); })
      .Case([&](arith::MulIOp) { return binary(BinaryKind::Mul); })
      .Case([&](arith::DivSIOp) { return binary(BinaryKind::Div); })
      .Case([&](arith::AddFOp) { return binary(BinaryKind::Add); })
      .Case([&](arith::SubFOp) { return binary(BinaryKind::Sub); })
      .Case([&](arith::MulFOp) { return binary(BinaryKind::Mul); })
      .Case([&](arith::DivFOp) { return binary(BinaryKind::Div); })
      .Case([&](arith::NegFOp neg) -> LogicalResult {
        FailureOr<Value> operand = lookup(neg.getOperand(), op);
        if (failed(operand)) {
          return failure();
        }
        values[neg.getResult()] = UnaryOp::create(builder, loc, UnaryKind::Neg, *operand);
        return success();
      })
      .Case([&](arith::SIToFPOp convert) -> LogicalResult {
        if (convert.getType() != floatType) {
          return op->emitError() << "only conversions to the target's 'float', " << floatType
                                 << ", can be converted to OpenQASM";
        }
        FailureOr<Value> operand = lookup(convert.getIn(), op);
        if (failed(operand)) {
          return failure();
        }
        values[convert.getResult()] =
            CastOp::create(builder, loc, UnsizedFloatType::get(context), *operand, /*implicit=*/true);
        return success();
      })
      .Case<arith::IndexCastOp, arith::ExtSIOp>([&](Operation*) { return forward(); })
      .Case([&](arith::ExtFOp extend) -> LogicalResult {
        // Widening the target's `float` to an `f64` gate parameter: the implicit cast to `angle` takes its place.
        if (extend.getIn().getType() != floatType || !extend.getType().isF64()) {
          return op->emitError() << "only the extension of the target's 'float', " << floatType
                                 << ", to 'f64' can be converted to OpenQASM";
        }
        return forward();
      })
      .Case([&](StaticRefOp staticRef) -> LogicalResult {
        for (auto [result, index] : llvm::zip_equal(staticRef.getQubits(), staticRef.getIndices())) {
          values[result] = PhysicalQubitOp::create(builder, loc, QubitRefType::get(context), index);
        }
        return success();
      })
      .Case([&](AllocOp alloc) { return translateAlloc(alloc); })
      .Case([&](DeallocOp) {
        // OpenQASM qubits live until the end of the program.
        return success();
      })
      .Case([&](tensor::ExtractOp extract) -> LogicalResult {
        if (!isa<QubitRefType>(extract.getType()) || extract.getIndices().size() != 1) {
          return op->emitError() << "only the extraction of a qubit from an array can be converted to OpenQASM";
        }
        FailureOr<Value> reg = lookup(extract.getTensor(), op);
        FailureOr<Value> index = lookup(extract.getIndices()[0], op);
        if (failed(reg) || failed(index)) {
          return failure();
        }
        values[extract.getResult()] = QubitIndexOp::create(builder, loc, *reg, *index);
        return success();
      })
      .Case([&](memref::AllocaOp alloca) { return translateAlloca(alloca); })
      .Case([&](memref::CastOp) { return forward(); })
      .Case([&](memref::SubViewOp subview) { return translateSubview(subview); })
      .Case([&](memref::StoreOp store) { return translateStore(store); })
      .Case([&](memref::LoadOp load) { return translateLoad(load); })
      .Case([&](qref::SingleOp single) { return translateSingle(single); })
      .Case([&](qref::PairOp pair) { return translatePair(pair); })
      .Case([&](qref::MeasureOp measure) { return translateMeasure(measure); })
      .Case([&](qref::ResetOp reset) -> LogicalResult {
        FailureOr<Value> qubit = lookup(reset.getQubit(), op);
        if (failed(qubit)) {
          return failure();
        }
        ResetOp::create(builder, loc, *qubit);
        // |+> = h |0>.
        if (reset.getBasis() == Basis::X) {
          call(loc, "h", {}, *qubit);
        }
        return success();
      })
      .Default([&](Operation*) -> LogicalResult {
        return op->emitError() << "'" << op->getName() << "' cannot be converted to OpenQASM";
      });
}

LogicalResult Translator::translateConstant(arith::ConstantOp op) {
  Location loc = op.getLoc();
  MLIRContext* context = builder.getContext();
  if (auto integer = dyn_cast<IntegerAttr>(op.getValue())) {
    if (integer.getType().isInteger(1)) {
      Value literal = createInt(loc, llvm::APInt(64, integer.getValue().getZExtValue()));
      values[op.getResult()] = CastOp::create(builder, loc, BitType::get(context), literal, /*implicit=*/true);
      return success();
    }
    if (isa<IndexType>(integer.getType()) || integer.getType().isSignlessInteger()) {
      values[op.getResult()] = createInt(loc, integer.getValue().sextOrTrunc(64));
      return success();
    }
  }
  if (auto real = dyn_cast<FloatAttr>(op.getValue()); real && real.getType() == floatType) {
    if (!real.getValue().isFinite()) {
      return op.emitError() << "non-finite constant cannot be converted to OpenQASM";
    }
    values[op.getResult()] = createFloat(loc, real.getValue());
    return success();
  }
  return op.emitError() << "a constant " << op.getValue() << " cannot be converted to OpenQASM";
}

LogicalResult Translator::translateAlloc(AllocOp op) {
  Location loc = op.getLoc();
  MLIRContext* context = builder.getContext();
  const std::string name = freshName("q");
  if (isa<QubitRefType>(op.getType())) {
    values[op.getResult()] = QubitDeclOp::create(builder, loc, QubitRefType::get(context), name, Value());
    return success();
  }
  auto array = cast<RankedTensorType>(op.getType());
  assert(array && "only a qubit or a tensor of qubits can be allocated");

  if (array.isDynamicDim(0)) {
    return op.emitError() << "an array of qubits of dynamic size cannot be converted to OpenQASM";
  }
  const int64_t size = array.getDimSize(0);
  Value designator = createInt(loc, llvm::APInt(64, size));
  values[op.getResult()] = QubitDeclOp::create(builder, loc, QRegType::get(context, size), name, designator);
  return success();
}

LogicalResult Translator::translateAlloca(memref::AllocaOp op) {
  Location loc = op.getLoc();
  MLIRContext* context = builder.getContext();
  MemRefType type = op.getType();
  if (!type.getElementType().isInteger(1) || type.getRank() > 1 || !type.hasStaticShape() ||
      !type.getLayout().isIdentity()) {
    return op.emitError() << "only the storage of a 'bit' or 'bit[n]', 'memref<i1>' or 'memref<nxi1>', can be "
                             "converted to OpenQASM, got "
                          << type;
  }
  const std::string name = freshName("c");
  if (type.getRank() == 0) {
    values[op.getResult()] =
        DeclareOp::create(builder, loc, RefType::get(BitType::get(context)), name, Value(), Value());
    return success();
  }
  const int64_t size = type.getDimSize(0);
  Value designator = createInt(loc, llvm::APInt(64, size));
  values[op.getResult()] =
      DeclareOp::create(builder, loc, RefType::get(BitsType::get(context, size)), name, designator, Value());
  return success();
}

LogicalResult Translator::translateSubview(memref::SubViewOp op) {
  if (op.getSourceType().getRank() != 1 || op.getType().getRank() != 0) {
    return op.emitError() << "only the view of one bit of a register can be converted to OpenQASM";
  }
  FailureOr<Value> ref = lookup(op.getSource(), op);
  if (failed(ref)) {
    return failure();
  }
  Value index;
  OpFoldResult offset = op.getMixedOffsets()[0];
  if (auto dynamicOffset = dyn_cast<Value>(offset)) {
    FailureOr<Value> translatedOffset = lookup(dynamicOffset, op);
    if (failed(translatedOffset)) {
      return failure();
    }
    index = *translatedOffset;
  } else {
    index = createInt(op.getLoc(), cast<IntegerAttr>(cast<Attribute>(offset)).getValue().sextOrTrunc(64));
  }
  values[op.getResult()] =
      SubrefOp::create(builder, op.getLoc(), RefType::get(BitType::get(builder.getContext())), *ref, index);
  return success();
}

LogicalResult Translator::translateStore(memref::StoreOp op) {
  Location loc = op.getLoc();
  FailureOr<Value> ref = lookup(op.getMemRef(), op);
  if (failed(ref)) {
    return failure();
  }
  if (!op.getIndices().empty()) {
    FailureOr<Value> index = lookup(op.getIndices()[0], op);
    if (failed(index)) {
      return failure();
    }
    ref = SubrefOp::create(builder, loc, RefType::get(BitType::get(builder.getContext())), *ref, *index).getResult();
  }
  // A measurement that this store consumes is created right before it, see `translateMeasure`.
  Value value = op.getValueToStore();
  if (Operation* measure = pendingMeasurements.lookup(value); measure != nullptr) {
    FailureOr<Value> qubit = lookup(measure->getOperand(0), measure);
    if (failed(qubit)) {
      return failure();
    }
    values[value] = MeasureOp::create(builder, measure->getLoc(), BitType::get(builder.getContext()), *qubit);
  }
  FailureOr<Value> translatedValue = lookup(value, op);
  if (failed(translatedValue)) {
    return failure();
  }
  RefStoreOp::create(builder, loc, *translatedValue, *ref);
  return success();
}

LogicalResult Translator::translateLoad(memref::LoadOp op) {
  if (!op.getIndices().empty()) {
    return op.emitError() << "reading a bit of a register cannot be converted to OpenQASM";
  }
  // A load is printed at its use, so it is created there.
  FailureOr<Value> ref = lookup(op.getMemRef(), op);
  if (failed(ref)) {
    return failure();
  }
  storedBits[op.getResult()] = *ref;
  return success();
}

LogicalResult Translator::translateSingle(qref::SingleOp op) {
  Location loc = op.getLoc();
  FailureOr<Value> qubit = lookup(op.getQubit(), op);
  if (failed(qubit)) {
    return failure();
  }
  SmallVector<Value> params;
  for (Value param : op.getParams()) {
    FailureOr<Value> angle = lookupAngle(param, op);
    if (failed(angle)) {
      return failure();
    }
    params.push_back(*angle);
  }

  const SingleGateKind kind = op.getGateKind();
  if (const std::optional<StringRef> name = getStandardGateName(kind)) {
    call(loc, *name, params, *qubit);
    return success();
  }
  // TODO: Once custom gates are supported, create gate definitions for the qref gates that don't directly map to oq3
  // gates, and call them here.
  switch (kind) {
  case SingleGateKind::SXdg:
    // sxdg = rx(-π/2), up to a global phase.
    call(loc, "rx", createNegHalfPi(loc), *qubit);
    return success();
  case SingleGateKind::UZYZ:
    // u_zyz(z1, y, z2) = rz(z2) ry(y) rz(z1) = U(y, z2, z1), up to a global phase.
    call(loc, "U", {params[1], params[2], params[0]}, *qubit);
    return success();
  default:
    return op.emitError() << "the gate '" << stringifySingleGateKind(kind) << "' cannot be converted to OpenQASM";
  }
}

LogicalResult Translator::translatePair(qref::PairOp op) {
  const PairGateKind kind = op.getGateKind();
  const std::optional<StringRef> name = getStandardGateName(kind);
  if (!name) {
    return op.emitError() << "the gate '" << stringifyPairGateKind(kind) << "' cannot be converted to OpenQASM";
  }

  FailureOr<Value> lhs = lookup(op.getLhs(), op);
  FailureOr<Value> rhs = lookup(op.getRhs(), op);
  if (failed(lhs) || failed(rhs)) {
    return failure();
  }
  SmallVector<Value> params;
  for (Value param : op.getParams()) {
    FailureOr<Value> angle = lookupAngle(param, op);
    if (failed(angle)) {
      return failure();
    }
    params.push_back(*angle);
  }
  call(op.getLoc(), *name, params, {*lhs, *rhs});
  return success();
}

/// When translating a measurement, there are three cases (qref on the left, oq3 on the right):
/// 1. The result is not stored:
///    ```
///    %b = qref.measure z %q : !qcc.qubit_ref -> i1  |  %b = oq3.measure %q : !qcc.qubit_ref -> !oq3.bit
///    // %b has no use
///    ```
/// 2. The result is stored directly into a bit or register, with only memory-effect-free ops between the measurement
///    and the store:
///    ```
///    %b = qref.measure z %q : !qcc.qubit_ref -> i1  |  // (unrelated ops)
///    // (some unrelated ops in between)             |  %b = oq3.measure %q : !qcc.qubit_ref -> !oq3.bit
///    memref.store %b, %c[] : memref<i1>             |  qcc.ref.store %b, %c : !qcc.ref<!oq3.bit>
///    ```
///    We keep track of these kinds of measurements in `pendingMeasurements` and realize them in the translation of the
///    store.
/// 3. The result is used in some other way, e.g. in the x basis, or stored more than once:
///    ```
///    %b = qref.measure x %q : !qcc.qubit_ref -> i1  |  oq3.gate_call @h [%q : !qcc.qubit_ref]
///                                                   |  %0 = oq3.measure %q : !qcc.qubit_ref -> !oq3.bit
///                                                   |  %m = oq3.declare "m0" = %0 : !oq3.bit : !qcc.ref<!oq3.bit>
///                                                   |  oq3.gate_call @h [%q : !qcc.qubit_ref]
///    memref.store %b, %c[] : memref<i1>             |  %1 = qcc.ref.load %m : !qcc.ref<!oq3.bit>
///                                                   |  qcc.ref.store %1, %c : !qcc.ref<!oq3.bit>
///    ```
///    This translation creates the measurement and the temporary bit, which is kept in `storedMeasurementResults`.
LogicalResult Translator::translateMeasure(qref::MeasureOp op) {
  Location loc = op.getLoc();
  MLIRContext* context = builder.getContext();
  FailureOr<Value> qubit = lookup(op.getQubit(), op);
  if (failed(qubit)) {
    return failure();
  }
  const bool isZ = op.getBasis() == Basis::Z;
  const bool isX = op.getBasis() == Basis::X;
  Value bit = op.getBit();

  if (bit.use_empty() && isZ) {
    MeasureOp::create(builder, loc, BitType::get(context), *qubit);
    return success();
  }
  if (isZ && bit.hasOneUse()) {
    auto store = dyn_cast<memref::StoreOp>(*bit.user_begin());
    if (store && store.getValueToStore() == bit && store->getBlock() == op->getBlock() &&
        onlyMemoryEffectFreeOpsBetween(op, store)) {
      // Measure-store pair: the measurement creation is deferred to the store.
      // We can then avoid creating temporary bits in oq3.
      pendingMeasurements[bit] = op;
      return success();
    }
  }

  // Measuring in the x basis is measuring in the z basis between Hadamard gates.
  if (isX) {
    call(loc, "h", {}, *qubit);
  }
  Value measure = MeasureOp::create(builder, loc, BitType::get(context), *qubit);
  storedBits[bit] =
      DeclareOp::create(builder, loc, RefType::get(BitType::get(context)), freshName("m"), Value(), measure);
  if (isX) {
    call(loc, "h", {}, *qubit);
  }
  return success();
}

//===----------------------------------------------------------------------===//
// Pass
//===----------------------------------------------------------------------===//

/// The IEEE 754 binary floating-point type of `width` bits, the target's `float`, or null if there is none.
static Type getFloatType(MLIRContext* context, unsigned width) {
  switch (width) {
  case 16:
    return Float16Type::get(context);
  case 32:
    return Float32Type::get(context);
  case 64:
    return Float64Type::get(context);
  case 128:
    return Float128Type::get(context);
  default:
    return {};
  }
}

namespace {

struct ConvertQRefToOQ3 final : qcc::impl::ConvertQRefToOQ3Base<ConvertQRefToOQ3> {
  using ConvertQRefToOQ3Base::ConvertQRefToOQ3Base;

protected:
  void runOnOperation() override {
    ModuleOp module = getOperation();
    MLIRContext* context = &getContext();

    SmallVector<FunctionOpInterface> entryPoints = getEntryPoints(module);
    auto entry = entryPoints.size() == 1 ? dyn_cast<func::FuncOp>(entryPoints[0].getOperation()) : nullptr;
    if (entry == nullptr || entry.isExternal()) {
      module.emitError() << "expected exactly one entry function ('" << QccDialect::EntryPointAttrHelper::getNameStr()
                         << "') to convert to OpenQASM";
      signalPassFailure();
      return;
    }
    if (entry.getNumArguments() != 0 || entry.getNumResults() != 0) {
      entry.emitError() << "an entry function with arguments or results cannot be converted to OpenQASM";
      signalPassFailure();
      return;
    }
    if (!entry.getBody().hasOneBlock()) {
      entry.emitError() << "an entry function with more than one block cannot be converted to OpenQASM";
      signalPassFailure();
      return;
    }
    for (Operation& op : *module.getBody()) {
      if (&op != entry.getOperation()) {
        op.emitError() << "only the entry function can be converted to OpenQASM";
        signalPassFailure();
        return;
      }
    }

    const unsigned wordSize =
        static_cast<unsigned>(DataLayout::closest(module).getTypeSizeInBits(IndexType::get(context)).getFixedValue());
    Type floatType = getFloatType(context, wordSize);
    if (floatType == nullptr) {
      module.emitError() << "there is no " << wordSize << "-bit 'float' for the target's word size";
      signalPassFailure();
      return;
    }
    if (failed(Translator(entry, floatType).run())) {
      signalPassFailure();
      return;
    }
    if (!module->hasAttr(OQ3Dialect::VersionAttrHelper::getNameStr())) {
      module->setAttr(OQ3Dialect::VersionAttrHelper::getNameStr(),
                      VersionAttr::get(context, defaultMajorVersion, defaultMinorVersion));
    }
  }
};

} // namespace
