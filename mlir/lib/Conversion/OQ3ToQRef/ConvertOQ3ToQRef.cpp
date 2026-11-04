// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/OQ3ToQRef/OQ3ToQRef.h"
#include "qcc/Dialect/OQ3/IR/OQ3.h"
#include "qcc/Dialect/QRef/IR/QRef.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/APFloat.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/Error.h"

#include <cassert>
#include <cstdint>
#include <numbers>
#include <optional>

namespace qcc {
#define GEN_PASS_DEF_CONVERTOQ3TOQREF
#include "qcc/Conversion/OQ3ToQRef/OQ3ToQRef.h.inc"
} // namespace qcc

using namespace mlir;
using namespace qcc;
using namespace qcc::oq3;

//===----------------------------------------------------------------------===//
// Types
//===----------------------------------------------------------------------===//

namespace {

/// Lowers the unsized `int` and `float`, whose width the target defines, to `intType` and `floatType`.
class OQ3TypeConverter final : public TypeConverter {
public:
  OQ3TypeConverter(MLIRContext* context, IntegerType intType, Type floatType) {
    addConversion([](Type type) { return type; });
    addConversion([intType](UnsizedIntType) -> Type { return intType; });
    addConversion([floatType](UnsizedFloatType) -> Type { return floatType; });
    // Gate parameters are `f64`, independent of the target. TODO: Change once angle type used in qref.
    addConversion([context](AngleType) -> Type { return Float64Type::get(context); });
    addConversion([context](BitType) -> Type { return IntegerType::get(context, 1); });
    addConversion([context](BitsType bits) -> Type {
      return RankedTensorType::get({bits.getSize()}, IntegerType::get(context, 1));
    });
    addConversion(
        [context](QRegType reg) -> Type { return RankedTensorType::get({reg.getSize()}, QubitRefType::get(context)); });
    addConversion([context](RefType ref) -> Type {
      return TypeSwitch<Type, Type>(ref.getElementType())
          .Case([&](BitType) {
            return MemRefType::get({}, IntegerType::get(context, 1),
                                   StridedLayoutAttr::get(context, ShapedType::kDynamic, /*strides=*/{}));
          })
          .Case([&](BitsType bits) { return MemRefType::get({bits.getSize()}, IntegerType::get(context, 1)); })
          .Default([&](Type) { return ref; });
    });
  }
};

} // namespace

//===----------------------------------------------------------------------===//
// Helpers
//===----------------------------------------------------------------------===//

static Value createFloat(OpBuilder& builder, Location loc, Type type, double value) {
  return arith::ConstantOp::create(builder, loc, builder.getFloatAttr(type, value));
}

static Value createIndex(OpBuilder& builder, Location loc, int64_t value) {
  return arith::ConstantIndexOp::create(builder, loc, value);
}

/// Parses OQ3's FloatLiteralAttr as a value of `type`.
static FailureOr<llvm::APFloat> parseFloatLiteral(FloatLiteralAttr literal, FloatType type,
                                                  function_ref<InFlightDiagnostic()> emitError) {
  llvm::APFloat value(type.getFloatSemantics());
  // The attribute's verifier checked that the text parses.
  const llvm::APFloat::opStatus status =
      llvm::cantFail(value.convertFromString(literal.getText(), llvm::APFloat::rmNearestTiesToEven));
  if ((status & llvm::APFloat::opOverflow) != 0) {
    return emitError() << "the floating-point literal does not fit into the " << type.getWidth() << " bits of 'float'";
  }
  return value;
}

/// Reduces the angle `radians` to [0, 2π).
static Value wrapAngle(OpBuilder& builder, Location loc, Value radians) {
  Type type = radians.getType();
  Value twoPi = createFloat(builder, loc, type, 2 * std::numbers::pi);
  // `remf` keeps the sign of its first operand, so a negative remainder is shifted by one period.
  Value remainder = arith::RemFOp::create(builder, loc, radians, twoPi);
  Value isNegative =
      arith::CmpFOp::create(builder, loc, arith::CmpFPredicate::OLT, remainder, createFloat(builder, loc, type, 0.0));
  Value shifted = arith::AddFOp::create(builder, loc, remainder, twoPi);
  return arith::SelectOp::create(builder, loc, isNegative, shifted, remainder);
}

/// Given a (possibly negative, counting from the end) `index` of something of `size` elements, returns the non-negative
/// `position`.
static Value createPosition(OpBuilder& builder, Location loc, Value index, int64_t size) {
  const int64_t value = *evaluateConstantInt(index);
  return createIndex(builder, loc, value < 0 ? value + size : value);
}

/// Returns the qubit with position `position` of `qubits`, a qubit or an array of them. A single qubit is the same
/// for every position, which is how gate calls broadcast.
static Value getQubitAt(OpBuilder& builder, Location loc, Value qubits, int64_t position) {
  if (isa<QubitRefType>(qubits.getType())) {
    return qubits;
  }
  return tensor::ExtractOp::create(builder, loc, qubits, createIndex(builder, loc, position));
}

/// Returns the qubit at the dynamic position `position` of `qubits`, a qubit or an array of them.
static Value getQubitAt(OpBuilder& builder, Location loc, Value qubits, Value position) {
  if (isa<QubitRefType>(qubits.getType())) {
    return qubits;
  }
  return tensor::ExtractOp::create(builder, loc, qubits, position);
}

/// Wraps `body` in an `scf.parallel` over the range [0, `count`), or builds `body`
///  - once if `hasRegister` is false (in this case, `body` must ignore its last argument),
//   - once if `count` is 1,
//   - not at all if `count` is 0.
static void buildBroadcast(OpBuilder& builder, Location loc, bool hasRegister, int64_t count,
                           function_ref<void(OpBuilder&, Location, Value)> body) {
  if (!hasRegister) {
    body(builder, loc, Value());
    return;
  }
  if (count == 1) {
    body(builder, loc, createIndex(builder, loc, 0));
    return;
  }
  if (count == 0) {
    return;
  }
  Value lower = createIndex(builder, loc, 0);
  Value upper = createIndex(builder, loc, count);
  Value step = createIndex(builder, loc, 1);
  scf::ParallelOp::create(
      builder, loc, lower, upper, step,
      [&](OpBuilder& nested, Location nestedLoc, ValueRange positions) { body(nested, nestedLoc, positions.front()); });
}

static int64_t getNumQubits(Value qubits) {
  if (auto array = dyn_cast<RankedTensorType>(qubits.getType())) {
    return array.getDimSize(0);
  }
  return 1;
}

/// Writes `value`, an `i1` or a `tensor<nxi1>`, to `storage`, a 0-d or 1-d memref.
static void storeBits(OpBuilder& builder, Location loc, Value value, Value storage) {
  auto storageType = cast<MemRefType>(storage.getType());
  if (storageType.getRank() == 0) {
    memref::StoreOp::create(builder, loc, value, storage, ValueRange());
    return;
  }
  for (int64_t i = 0; i < storageType.getDimSize(0); ++i) {
    Value position = createIndex(builder, loc, i);
    Value bit = tensor::ExtractOp::create(builder, loc, value, position);
    memref::StoreOp::create(builder, loc, bit, storage, position);
  }
}

/// Reads `storage`, a 0-d or 1-d memref of `i1`, as an `i1` or a `tensor<nxi1>`.
static Value loadBits(OpBuilder& builder, Location loc, Value storage) {
  auto storageType = cast<MemRefType>(storage.getType());
  if (storageType.getRank() == 0) {
    return memref::LoadOp::create(builder, loc, storage, ValueRange());
  }
  SmallVector<Value> bits;
  for (int64_t i = 0; i < storageType.getDimSize(0); ++i) {
    bits.push_back(memref::LoadOp::create(builder, loc, storage, createIndex(builder, loc, i)));
  }
  auto type = RankedTensorType::get({storageType.getDimSize(0)}, storageType.getElementType());
  return tensor::FromElementsOp::create(builder, loc, type, bits);
}

//===----------------------------------------------------------------------===//
// Gates
//===----------------------------------------------------------------------===//

/// The `qref` gate a single-qubit standard gate maps to, with the same parameters.
static std::optional<SingleGateKind> getSingleGateKind(StringRef name) {
  return llvm::StringSwitch<std::optional<SingleGateKind>>(name)
      .Case("x", SingleGateKind::X)
      .Case("y", SingleGateKind::Y)
      .Case("z", SingleGateKind::Z)
      .Case("h", SingleGateKind::H)
      .Case("s", SingleGateKind::S)
      .Case("sdg", SingleGateKind::Sdg)
      .Case("t", SingleGateKind::T)
      .Case("tdg", SingleGateKind::Tdg)
      .Case("sx", SingleGateKind::SX)
      .Case("rx", SingleGateKind::RX)
      .Case("ry", SingleGateKind::RY)
      // `p(λ)` is `rz(λ)` up to a global phase.
      .Cases({"rz", "p", "phase", "u1"}, SingleGateKind::RZ)
      .Default(std::nullopt);
}

/// The `qref` gate a two-qubit standard gate maps to, with the same parameters.
static std::optional<PairGateKind> getPairGateKind(StringRef name) {
  return llvm::StringSwitch<std::optional<PairGateKind>>(name)
      .Cases({"cx", "CX"}, PairGateKind::CX)
      .Case("cy", PairGateKind::CY)
      .Case("cz", PairGateKind::CZ)
      .Case("swap", PairGateKind::SWAP)
      .Cases({"cp", "cphase"}, PairGateKind::CP)
      .Default(std::nullopt);
}

/// Whether `name`, a gate of `stdgates.inc` or a built-in gate, maps to at most one `qref` gate.
static bool isConvertibleGate(StringRef name) {
  return getSingleGateKind(name) || getPairGateKind(name) ||
         llvm::is_contained({"id", "gphase", "U", "u3", "u2"}, name);
}

static void buildGate(OpBuilder& builder, Location loc, StringRef name, ValueRange params, ValueRange qubits) {
  if (const std::optional<SingleGateKind> kind = getSingleGateKind(name)) {
    qref::SingleOp::create(builder, loc, *kind, qubits[0], params);
    return;
  }
  if (const std::optional<PairGateKind> kind = getPairGateKind(name)) {
    qref::PairOp::create(builder, loc, *kind, qubits[0], qubits[1], params);
    return;
  }
  // U(θ, φ, λ) = rz(φ) ry(θ) rz(λ) up to a global phase, and u2(φ, λ) = U(π/2, φ, λ).
  if (name == "U" || name == "u3") {
    qref::SingleOp::create(builder, loc, SingleGateKind::UZYZ, qubits[0], {params[2], params[0], params[1]});
    return;
  }
  if (name == "u2") {
    Value halfPi = createFloat(builder, loc, params[0].getType(), std::numbers::pi / 2);
    qref::SingleOp::create(builder, loc, SingleGateKind::UZYZ, qubits[0], {params[1], halfPi, params[0]});
    return;
  }
  // `id` acts trivially, `gphase` only on the global phase, which `qref` does not model.
  assert((name == "id" || name == "gphase") && "the gate must be convertible");
}

//===----------------------------------------------------------------------===//
// Patterns: program structure
//===----------------------------------------------------------------------===//

namespace {

template <typename SourceOp> struct EraseLowering final : public OpConversionPattern<SourceOp> {
  using OpConversionPattern<SourceOp>::OpConversionPattern;

  LogicalResult matchAndRewrite(SourceOp op, typename SourceOp::Adaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    rewriter.eraseOp(op);
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Patterns: qubits
//===----------------------------------------------------------------------===//

struct QubitDeclLowering final : public OpConversionPattern<QubitDeclOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(QubitDeclOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    Type type = getTypeConverter()->convertType(op.getType());
    rewriter.replaceOpWithNewOp<AllocOp>(op, type, /*dynamic_size=*/Value());
    return success();
  }
};

struct PhysicalQubitLowering final : public OpConversionPattern<PhysicalQubitOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(PhysicalQubitOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    rewriter.replaceOpWithNewOp<StaticRefOp>(op, ArrayRef<int64_t>{op.getIndexAttr().getInt()});
    return success();
  }
};

struct QubitIndexLowering final : public OpConversionPattern<QubitIndexOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(QubitIndexOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    Value position = createPosition(rewriter, op.getLoc(), op.getIndex(), op.getReg().getType().getSize());
    rewriter.replaceOpWithNewOp<tensor::ExtractOp>(op, adaptor.getReg(), position);
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Patterns: classical storage
//===----------------------------------------------------------------------===//

struct DeclareLowering final : public OpConversionPattern<DeclareOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(DeclareOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    Location loc = op.getLoc();
    auto type = cast<MemRefType>(getTypeConverter()->convertType(op.getType()));
    Value storage;
    if (type.getRank() == 0) {
      // The storage of a `bit` has a dynamic offset, see `getBitStorageType`.
      auto allocaType = MemRefType::get({}, type.getElementType());
      storage = memref::CastOp::create(rewriter, loc, type, memref::AllocaOp::create(rewriter, loc, allocaType));
    } else {
      storage = memref::AllocaOp::create(rewriter, loc, type);
    }
    if (adaptor.getInit()) {
      storeBits(rewriter, loc, adaptor.getInit(), storage);
    }
    rewriter.replaceOp(op, storage);
    return success();
  }
};

struct SubrefLowering final : public OpConversionPattern<SubrefOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(SubrefOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    Location loc = op.getLoc();
    const int64_t size = cast<BitsType>(op.getRef().getType().getElementType()).getSize();
    Value position = createPosition(rewriter, loc, op.getIndex(), size);
    // A rank-reducing subview of one bit. The offset is an operand even if it is constant, so that the result has the
    // dynamic offset of `getBitStorageType`.
    auto type = cast<MemRefType>(getTypeConverter()->convertType(op.getType()));
    rewriter.replaceOpWithNewOp<memref::SubViewOp>(op, type, adaptor.getRef(), ArrayRef<OpFoldResult>{position},
                                                   ArrayRef<OpFoldResult>{rewriter.getIndexAttr(1)},
                                                   ArrayRef<OpFoldResult>{rewriter.getIndexAttr(1)});
    return success();
  }
};

struct RefLoadLowering final : public OpConversionPattern<RefLoadOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(RefLoadOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    if (!isa<MemRefType>(adaptor.getRef().getType())) {
      return rewriter.notifyMatchFailure(op, "not a reference to bits");
    }
    rewriter.replaceOp(op, loadBits(rewriter, op.getLoc(), adaptor.getRef()));
    return success();
  }
};

struct RefStoreLowering final : public OpConversionPattern<RefStoreOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(RefStoreOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    if (!isa<MemRefType>(adaptor.getRef().getType())) {
      return rewriter.notifyMatchFailure(op, "not a reference to bits");
    }
    storeBits(rewriter, op.getLoc(), adaptor.getValue(), adaptor.getRef());
    rewriter.eraseOp(op);
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Patterns: expressions
//===----------------------------------------------------------------------===//

struct ConstantLowering final : public OpConversionPattern<ConstantOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(ConstantOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    Type type = getTypeConverter()->convertType(op.getType());
    TypedAttr value =
        TypeSwitch<Attribute, TypedAttr>(op.getValue())
            .Case([&](IntLiteralAttr literal) -> TypedAttr {
              // The pass checked that the literal fits.
              return rewriter.getIntegerAttr(type, literal.getValue().zextOrTrunc(type.getIntOrFloatBitWidth()));
            })
            .Case([&](FloatLiteralAttr literal) -> TypedAttr {
              // The pass checked that the value fits.
              return rewriter.getFloatAttr(
                  type, *parseFloatLiteral(literal, cast<FloatType>(type), [&] { return op.emitError(); }));
            })
            .Case([&](BitstringAttr literal) -> TypedAttr {
              const llvm::APInt& bits = literal.getValue();
              SmallVector<bool> elements;
              for (unsigned i = 0; i < bits.getBitWidth(); ++i) {
                elements.push_back(bits[i]);
              }
              return DenseElementsAttr::get(cast<ShapedType>(type), ArrayRef<bool>(elements));
            })
            .Default([](Attribute) { return TypedAttr(); });
    if (!value) {
      return rewriter.notifyMatchFailure(op, "unsupported literal");
    }
    rewriter.replaceOpWithNewOp<arith::ConstantOp>(op, value);
    return success();
  }
};

struct MathConstantLowering final : public OpConversionPattern<MathConstantOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(MathConstantOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    double value = 0.0;
    switch (op.getKind()) {
    case MathConstantKind::Pi:
      value = std::numbers::pi;
      break;
    case MathConstantKind::Tau:
      value = 2 * std::numbers::pi;
      break;
    case MathConstantKind::Euler:
      value = std::numbers::e;
      break;
    }
    Type type = getTypeConverter()->convertType(op.getType());
    rewriter.replaceOp(op, createFloat(rewriter, op.getLoc(), type, value));
    return success();
  }
};

struct UnaryLowering final : public OpConversionPattern<UnaryOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(UnaryOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    Location loc = op.getLoc();
    Value operand = adaptor.getOperand();
    // `neg` is the only unary operator so far.
    Value result;
    if (isa<UnsizedIntType>(op.getType())) {
      Value zero = arith::ConstantOp::create(rewriter, loc, rewriter.getIntegerAttr(operand.getType(), 0));
      result = arith::SubIOp::create(rewriter, loc, zero, operand);
    } else {
      result = arith::NegFOp::create(rewriter, loc, operand);
      if (isa<AngleType>(op.getType())) {
        result = wrapAngle(rewriter, loc, result);
      }
    }
    rewriter.replaceOp(op, result);
    return success();
  }
};

struct BinaryLowering final : public OpConversionPattern<BinaryOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(BinaryOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    Location loc = op.getLoc();
    Value lhs = adaptor.getLhs();
    Value rhs = adaptor.getRhs();
    const BinaryKind kind = op.getKind();

    if (isa<UnsizedIntType>(op.getType())) {
      Value result;
      switch (kind) {
      case BinaryKind::Add:
        result = arith::AddIOp::create(rewriter, loc, lhs, rhs);
        break;
      case BinaryKind::Sub:
        result = arith::SubIOp::create(rewriter, loc, lhs, rhs);
        break;
      case BinaryKind::Mul:
        result = arith::MulIOp::create(rewriter, loc, lhs, rhs);
        break;
      case BinaryKind::Div:
        result = arith::DivSIOp::create(rewriter, loc, lhs, rhs);
        break;
      }
      rewriter.replaceOp(op, result);
      return success();
    }

    // Both operands have the floating-point result type, except for an integer that scales an angle, which is converted
    // first.
    Type floatType = getTypeConverter()->convertType(op.getType());
    auto toFloat = [&](Value value) -> Value {
      if (isa<IntegerType>(value.getType())) {
        return arith::SIToFPOp::create(rewriter, loc, floatType, value);
      }
      return value;
    };
    lhs = toFloat(lhs);
    rhs = toFloat(rhs);
    Value result;
    switch (kind) {
    case BinaryKind::Add:
      result = arith::AddFOp::create(rewriter, loc, lhs, rhs);
      break;
    case BinaryKind::Sub:
      result = arith::SubFOp::create(rewriter, loc, lhs, rhs);
      break;
    case BinaryKind::Mul:
      result = arith::MulFOp::create(rewriter, loc, lhs, rhs);
      break;
    case BinaryKind::Div:
      result = arith::DivFOp::create(rewriter, loc, lhs, rhs);
      break;
    }
    if (isa<AngleType>(op.getType())) {
      result = wrapAngle(rewriter, loc, result);
    }
    rewriter.replaceOp(op, result);
    return success();
  }
};

struct CastLowering final : public OpConversionPattern<CastOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(CastOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    Location loc = op.getLoc();
    Value input = adaptor.getInput();
    Type from = op.getInput().getType();
    Type to = op.getType();
    Type resultType = getTypeConverter()->convertType(to);
    Value result;
    if (isa<UnsizedIntType>(from) && isa<UnsizedFloatType>(to)) {
      result = arith::SIToFPOp::create(rewriter, loc, resultType, input);
    } else if (isa<UnsizedIntType>(from) && isa<BitType>(to)) {
      // Every non-zero integer is a set bit.
      Value zero = arith::ConstantOp::create(rewriter, loc, rewriter.getIntegerAttr(input.getType(), 0));
      result = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::ne, input, zero);
    } else if (isa<UnsizedFloatType>(from) && isa<AngleType>(to)) {
      // The angle may be wider or narrower than the target's `float`.
      const unsigned fromWidth = input.getType().getIntOrFloatBitWidth();
      const unsigned toWidth = resultType.getIntOrFloatBitWidth();
      if (fromWidth < toWidth) {
        input = arith::ExtFOp::create(rewriter, loc, resultType, input);
      } else if (fromWidth > toWidth) {
        input = arith::TruncFOp::create(rewriter, loc, resultType, input);
      }
      result = wrapAngle(rewriter, loc, input);
    } else {
      return rewriter.notifyMatchFailure(op, "unsupported cast");
    }
    rewriter.replaceOp(op, result);
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Patterns: quantum instructions
//===----------------------------------------------------------------------===//

struct MeasureLowering final : public OpConversionPattern<MeasureOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(MeasureOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    Location loc = op.getLoc();
    Value qubits = adaptor.getQubits();
    if (isa<QubitRefType>(qubits.getType())) {
      rewriter.replaceOpWithNewOp<qref::MeasureOp>(op, Basis::Z, qubits);
      return success();
    }
    SmallVector<Value> bits;
    for (int64_t i = 0; i < getNumQubits(qubits); ++i) {
      bits.push_back(qref::MeasureOp::create(rewriter, loc, Basis::Z, getQubitAt(rewriter, loc, qubits, i)));
    }
    rewriter.replaceOpWithNewOp<tensor::FromElementsOp>(op, getTypeConverter()->convertType(op.getType()), bits);
    return success();
  }
};

struct ResetLowering final : public OpConversionPattern<ResetOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(ResetOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    Location loc = op.getLoc();
    Value qubits = adaptor.getQubits();
    buildBroadcast(rewriter, loc, isa<RankedTensorType>(qubits.getType()), getNumQubits(qubits),
                   [&](OpBuilder& builder, Location bodyLoc, Value position) {
                     qref::ResetOp::create(builder, bodyLoc, Basis::Z, getQubitAt(builder, bodyLoc, qubits, position));
                   });
    rewriter.eraseOp(op);
    return success();
  }
};

struct GateCallLowering final : public OpConversionPattern<GateCallOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(GateCallOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    Location loc = op.getLoc();
    int64_t count = 1;
    bool hasRegister = false;
    for (Value qubitArg : adaptor.getQubits()) {
      if (isa<RankedTensorType>(qubitArg.getType())) {
        hasRegister = true;
        count = getNumQubits(qubitArg);
        break; // The verifier checked that all registers have the same size.
      }
    }
    buildBroadcast(rewriter, loc, hasRegister, count, [&](OpBuilder& builder, Location bodyLoc, Value position) {
      SmallVector<Value> qubits = llvm::map_to_vector(
          adaptor.getQubits(), [&](Value qubitArg) { return getQubitAt(builder, bodyLoc, qubitArg, position); });
      buildGate(builder, bodyLoc, op.getCallee(), adaptor.getParams(), qubits);
    });
    rewriter.eraseOp(op);
    return success();
  }
};

} // namespace

//===----------------------------------------------------------------------===//
// Pass
//===----------------------------------------------------------------------===//

/// The target's word size in bits: the width of `index` in the module's data layout
/// (`dlti.dl_spec`), 64 if it has none. This is the width of `int` and `float`.
static unsigned getWordSize(ModuleOp module) {
  return static_cast<unsigned>(
      DataLayout::closest(module).getTypeSizeInBits(IndexType::get(module.getContext())).getFixedValue());
}

/// The IEEE 754 binary floating-point type of `width` bits, or null if there is none.
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

static LogicalResult checkPreconditions(ModuleOp module, IntegerType intType, Type floatType) {
  bool convertible = true;
  module.walk([&](Operation* op) {
    TypeSwitch<Operation*>(op)
        .Case<QubitIndexOp, SubrefOp>([&](Operation* indexing) {
          if (failed(evaluateConstantInt(indexing->getOperand(1)))) {
            indexing->emitError() << "an index that is not a constant expression cannot be converted to 'qref' yet";
            convertible = false;
          }
        })
        .Case([&](GateCallOp call) {
          if (!isConvertibleGate(call.getCallee())) {
            call.emitError() << "the gate '" << call.getCallee() << "' cannot be converted to 'qref' yet";
            convertible = false;
          }
        })
        .Case([&](DefinedOp marker) {
          marker.emitError() << "global definitions cannot be converted to 'qref' yet";
          convertible = false;
        })
        .Case([&](ConstantOp constant) {
          if (auto literal = dyn_cast<IntLiteralAttr>(constant.getValue());
              literal && literal.getValue().getActiveBits() >= intType.getWidth()) {
            constant.emitError() << "the integer literal does not fit into the " << intType.getWidth()
                                 << " bits of 'int'";
            convertible = false;
          }
          if (auto literal = dyn_cast<FloatLiteralAttr>(constant.getValue())) {
            if (failed(parseFloatLiteral(literal, cast<FloatType>(floatType), [&] { return constant.emitError(); }))) {
              convertible = false;
            }
          }
        });
  });
  return success(convertible);
}

namespace {

struct ConvertOQ3ToQRef final : qcc::impl::ConvertOQ3ToQRefBase<ConvertOQ3ToQRef> {
  using ConvertOQ3ToQRefBase::ConvertOQ3ToQRefBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    MLIRContext* context = &getContext();
    // The target defines the width of the unsized `int` and `float`; we choose its word size for both.
    const unsigned wordSize = getWordSize(module);
    Type floatType = getFloatType(context, wordSize);
    if (floatType == nullptr) {
      module.emitError() << "there is no " << wordSize << "-bit 'float' for the target's word size";
      signalPassFailure();
      return;
    }
    auto intType = IntegerType::get(context, wordSize);
    if (failed(checkPreconditions(module, intType, floatType))) {
      signalPassFailure();
      return;
    }

    OQ3TypeConverter typeConverter(context, intType, floatType);
    ConversionTarget target(*context);
    target.addIllegalDialect<OQ3Dialect>();
    target.addLegalDialect<arith::ArithDialect, memref::MemRefDialect, scf::SCFDialect, tensor::TensorDialect,
                           QccDialect, qref::QRefDialect, func::FuncDialect>();
    target.addLegalOp<ModuleOp>();
    target.addDynamicallyLegalOp<RefLoadOp, RefStoreOp>([&](Operation* op) { return typeConverter.isLegal(op); });

    RewritePatternSet patterns(context);
    patterns.add<EraseLowering<IncludeOp>, EraseLowering<PragmaOp>, EraseLowering<BarrierOp>, QubitDeclLowering,
                 PhysicalQubitLowering, QubitIndexLowering, DeclareLowering, SubrefLowering, RefLoadLowering,
                 RefStoreLowering, ConstantLowering, MathConstantLowering, UnaryLowering, BinaryLowering, CastLowering,
                 MeasureLowering, ResetLowering, GateCallLowering>(typeConverter, context);

    if (failed(applyPartialConversion(module, target, std::move(patterns)))) {
      signalPassFailure();
      return;
    }
    module->removeAttr(OQ3Dialect::VersionAttrHelper::getNameStr());
  }
};

} // namespace
