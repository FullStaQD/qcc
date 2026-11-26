// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/JaspToQRef/JaspToQRef.h" // IWYU pragma: keep
#include "qcc/Dialect/Jasp/IR/Jasp.h"
#include "qcc/Dialect/QRef/IR/QRef.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Func/Transforms/FuncConversions.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Support/LLVM.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSwitch.h"

#include <cassert>
#include <optional>
#include <utility>
#include <variant>

namespace qcc {

#define GEN_PASS_DEF_CONVERTJASPTOQREF
#include "qcc/Conversion/JaspToQRef/JaspToQRef.h.inc"

using namespace mlir;

namespace {

//===----------------------------------------------------------------------===//
// Gates
//===----------------------------------------------------------------------===//

/// The gate kind that a jasp gate becomes, or none if the gate is dropped.
using GateKind = std::variant<std::monostate, SingleGateKind, PairGateKind>;

/// A jasp gate: it takes `numQubits` qubits followed by `numParams` angles, and becomes a gate of `kind`.
struct GateInfo {
  unsigned numQubits;
  unsigned numParams;
  GateKind kind;
};

} // namespace

/// A jasp gate that becomes the single-qubit gate `kind`.
static GateInfo single(SingleGateKind kind) {
  return {.numQubits = 1, .numParams = SingleGateKindAttr::getNumParams(kind), .kind = kind};
}

/// A jasp gate that becomes the two-qubit gate `kind`. For a controlled gate, the control comes first.
static GateInfo pair(PairGateKind kind) {
  return {.numQubits = 2, .numParams = PairGateKindAttr::getNumParams(kind), .kind = kind};
}

/// A jasp gate that is dropped: it has no effect up to a global phase.
static GateInfo dropped(unsigned numQubits, unsigned numParams) {
  return {.numQubits = numQubits, .numParams = numParams, .kind = std::monostate()};
}

/// The jasp gate called `name`, if the pass supports it.
static std::optional<GateInfo> lookupGate(StringRef name) {
  return llvm::StringSwitch<std::optional<GateInfo>>(name)
      .Case("id", dropped(1, 0))
      .Case("gphase", dropped(0, 1))
      .Case("x", single(SingleGateKind::X))
      .Case("y", single(SingleGateKind::Y))
      .Case("z", single(SingleGateKind::Z))
      .Case("h", single(SingleGateKind::H))
      .Case("s", single(SingleGateKind::S))
      .Case("s_dg", single(SingleGateKind::Sdg))
      .Case("t", single(SingleGateKind::T))
      .Case("t_dg", single(SingleGateKind::Tdg))
      .Case("sx", single(SingleGateKind::SX))
      .Case("rx", single(SingleGateKind::RX))
      .Case("ry", single(SingleGateKind::RY))
      .Case("rz", single(SingleGateKind::RZ))
      .Case("p", single(SingleGateKind::RZ))
      .Case("u3", single(SingleGateKind::UZYZ))
      .Case("cx", pair(PairGateKind::CX))
      .Case("cy", pair(PairGateKind::CY))
      .Case("cz", pair(PairGateKind::CZ))
      .Case("swap", pair(PairGateKind::SWAP))
      .Case("cp", pair(PairGateKind::CP))
      .Case("crz", pair(PairGateKind::CRZ))
      .Case("rxx", pair(PairGateKind::RXX))
      .Case("rzz", pair(PairGateKind::RZZ))
      .Default(std::nullopt);
}

/// Checks that the pass supports every jasp op in `module`, and that each gate takes the operands its name implies.
static LogicalResult checkPreconditions(ModuleOp module, StringRef passName) {
  const WalkResult result = module.walk([&](Operation* op) {
    if (!isa_and_present<jasp::JaspDialect>(op->getDialect()) ||
        isa<jasp::CreateQuantumKernelOp, jasp::ConsumeQuantumKernelOp, jasp::CreateQubitsOp, jasp::GetQubitOp,
            jasp::GetSizeOp, jasp::MeasureOp, jasp::ResetOp, jasp::DeleteQubitsOp>(op)) {
      return WalkResult::advance();
    }
    auto gate = dyn_cast<jasp::QuantumGateOp>(op);
    if (!gate) {
      op->emitOpError() << "is not supported by " << passName;
      return WalkResult::interrupt();
    }

    const StringRef name = gate.getGateType();
    const std::optional<GateInfo> info = lookupGate(name);
    if (!info) {
      gate.emitOpError() << "applies gate '" << name << "', which " << passName << " does not support";
      return WalkResult::interrupt();
    }
    auto isQubit = [](Value operand) { return isa<jasp::QubitType>(operand.getType()); };
    const OperandRange operands = gate.getGateOperands();
    if (operands.size() != info->numQubits + info->numParams ||
        !llvm::all_of(operands.take_front(info->numQubits), isQubit) ||
        llvm::any_of(operands.drop_front(info->numQubits), isQubit)) {
      gate.emitOpError() << "applies gate '" << name << "' to " << operands.size() << " operands, but " << passName
                         << " expects " << info->numQubits << " qubits followed by " << info->numParams << " angles";
      return WalkResult::interrupt();
    }
    return WalkResult::advance();
  });
  return failure(result.wasInterrupted());
}

namespace {

//===----------------------------------------------------------------------===//
// Type conversion
//===----------------------------------------------------------------------===//

/// Type converter for the ops.
///
/// - `!jasp.Qubit` becomes `!qcc.qubit_ref`, and `!jasp.QubitArray` becomes `tensor<?x!qcc.qubit_ref>`.
/// - `!jasp.QuantumState` is left intact.
///   TODO: This is a hack. If we delete the QuantumState type here, conversion fails before any pattern is applied.
///   But if we leave it out, function signatures will not be updated. Therefore, we need two separate type converters.
///
/// In addition, the prevalent rank-0 tensors `tensor<i64>` and `tensor<f64>` become plain values wherever possible.
class JaspToQRefTypeConverter : public TypeConverter {
public:
  explicit JaspToQRefTypeConverter(MLIRContext* ctx) {
    // Identity conversion for all other types.
    addConversion([](Type type) { return type; });

    addConversion([ctx](jasp::QubitType /*type*/) -> Type { return QubitRefType::get(ctx); });
    addConversion([ctx](jasp::QubitArrayType /*type*/) -> Type {
      return RankedTensorType::get({ShapedType::kDynamic}, QubitRefType::get(ctx));
    });

    addConversion([](RankedTensorType type) -> std::optional<Type> {
      if (type.getRank() == 0) {
        return type.getElementType();
      }
      return std::nullopt; // Leave other tensors alone.
    });

    addTargetMaterialization([](OpBuilder& builder, Type /*type*/, ValueRange inputs, Location loc) -> Value {
      if (inputs.size() != 1 || !isa<TensorType>(inputs[0].getType())) {
        return nullptr;
      }
      return tensor::ExtractOp::create(builder, loc, inputs[0], ValueRange{});
    });

    addSourceMaterialization([](OpBuilder& builder, RankedTensorType type, ValueRange inputs, Location loc) -> Value {
      if (inputs.size() != 1 || !inputs[0].getType().isIntOrIndexOrFloat()) {
        return nullptr;
      }
      return tensor::FromElementsOp::create(builder, loc, type, inputs[0]);
    });
  }
};

/// Type converter for function signatures, calls, returns and structured control flow: in addition to the base
/// converter, `!jasp.QuantumState` is dropped.
class QuantumStateEliminator final : public JaspToQRefTypeConverter {
public:
  explicit QuantumStateEliminator(MLIRContext* ctx) : JaspToQRefTypeConverter(ctx) {
    addConversion([](jasp::QuantumStateType /*type*/, SmallVectorImpl<Type>& /*results*/) { return success(); });
  }
};

//===----------------------------------------------------------------------===//
// Patterns
//===----------------------------------------------------------------------===//

/// Erases `jasp.create_quantum_kernel`: `qref` ops act on the qubits in place and need no quantum state.
///
/// NOTE: For this to work, the IR must be ordered correctly at the start of this pass.
struct CreateQuantumKernelConversion final : OpConversionPattern<jasp::CreateQuantumKernelOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::CreateQuantumKernelOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    rewriter.eraseOp(op);
    return success();
  }
};

/// Converts `jasp.consume_quantum_kernel` into the constant `true`: the program is assumed to succeed.
struct ConsumeQuantumKernelConversion final : OpConversionPattern<jasp::ConsumeQuantumKernelOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::ConsumeQuantumKernelOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    rewriter.replaceOpWithNewOp<arith::ConstantIntOp>(op, rewriter.getI1Type(), 1);
    return success();
  }
};

/// Converts `jasp.create_qubits %n` into `qcc.alloc %n : tensor<?x!qcc.qubit_ref>`, with `%n` cast to `index`.
struct CreateQubitsConversion final : OpConversionPattern<jasp::CreateQubitsOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::CreateQubitsOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    const Location loc = op.getLoc();
    Value size = arith::IndexCastOp::create(rewriter, loc, rewriter.getIndexType(), adaptor.getAmount());
    const Type arrayType = getTypeConverter()->convertType(op.getResult().getType());
    auto alloc = AllocOp::create(rewriter, loc, arrayType, size);
    rewriter.replaceOpWithMultiple(op, {alloc.getQubits(), ValueRange()});
    return success();
  }
};

/// Converts `jasp.get_qubit %q, %i` into `tensor.extract %q[%i]`, with `%i` cast to `index`.
struct GetQubitConversion final : OpConversionPattern<jasp::GetQubitOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::GetQubitOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    Value index = arith::IndexCastOp::create(rewriter, op.getLoc(), rewriter.getIndexType(), adaptor.getPosition());
    rewriter.replaceOpWithNewOp<tensor::ExtractOp>(op, adaptor.getQbArray(), index);
    return success();
  }
};

/// Converts `jasp.get_size %q` into `tensor.dim %q, 0`, cast to `i64`.
struct GetSizeConversion final : OpConversionPattern<jasp::GetSizeOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::GetSizeOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    const Location loc = op.getLoc();
    Value size = tensor::DimOp::create(rewriter, loc, adaptor.getQbArray(), 0);
    rewriter.replaceOpWithNewOp<arith::IndexCastOp>(op, rewriter.getI64Type(), size);
    return success();
  }
};

/// Converts `jasp.delete_qubits` into `qcc.dealloc`.
struct DeleteQubitsConversion final : OpConversionPattern<jasp::DeleteQubitsOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::DeleteQubitsOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    DeallocOp::create(rewriter, op.getLoc(), adaptor.getQubits());
    rewriter.eraseOp(op);
    return success();
  }
};

/// Converts `jasp.quantum_gate` into `qref.single` or `qref.pair`, or drops it (see `lookupGate`).
struct QuantumGateConversion final : OpConversionPattern<jasp::QuantumGateOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::QuantumGateOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    const std::optional<GateInfo> gate = lookupGate(op.getGateType());
    assert(gate && "the preconditions rule out unknown gates");
    const ValueRange operands = adaptor.getGateOperands();
    const ValueRange qubits = operands.take_front(gate->numQubits);
    SmallVector<Value> params(operands.drop_front(gate->numQubits));

    const Location loc = op.getLoc();
    if (const auto* single = std::get_if<SingleGateKind>(&gate->kind)) {
      // Only `u3(theta, phi, lambda)` becomes `u_zyz(lambda, theta, phi)`.
      if (*single == SingleGateKind::UZYZ) {
        params = {params[2], params[0], params[1]};
      }
      qref::SingleOp::create(rewriter, loc, *single, qubits[0], params);
    } else if (const auto* pair = std::get_if<PairGateKind>(&gate->kind)) {
      qref::PairOp::create(rewriter, loc, *pair, qubits[0], qubits[1], params);
    }
    rewriter.eraseOp(op);
    return success();
  }
};

/// Converts `jasp.measure` into `qref.measure z`.
///
/// On an array, measures each qubit in an `scf.for` and packs the outcomes into an `i64`, the one of qubit `i` into
/// bit `i`. A single outcome is zero-extended if the result is wider than `i1`.
struct MeasureConversion final : OpConversionPattern<jasp::MeasureOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::MeasureOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    const Location loc = op.getLoc();
    Value qubits = adaptor.getMeasQ();
    const Type resultType = getTypeConverter()->convertType(op.getMeasRes().getType());
    assert(resultType && resultType.isSignlessInteger() && "the result is an integer");

    if (!isQubitArray(qubits.getType())) {
      Value bit = qref::MeasureOp::create(rewriter, loc, Basis::Z, qubits);
      if (!resultType.isInteger(1)) {
        bit = arith::ExtUIOp::create(rewriter, loc, resultType, bit);
      }
      rewriter.replaceOpWithMultiple(op, {bit, ValueRange()});
      return success();
    }

    // TODO: Clean up once a measurement into an integer is possible in qref. Until then, we pack the bits here.
    assert(resultType.isInteger(64) && "only packing into i64 integers is supported");
    const Type i64Type = rewriter.getI64Type();
    Value c0Index = arith::ConstantIndexOp::create(rewriter, loc, 0);
    Value c1Index = arith::ConstantIndexOp::create(rewriter, loc, 1);
    Value c0I64 = arith::ConstantIntOp::create(rewriter, loc, i64Type, 0);
    Value size = tensor::DimOp::create(rewriter, loc, qubits, c0Index);
    auto forOp = scf::ForOp::create(rewriter, loc, c0Index, size, c1Index, ValueRange{c0I64});

    rewriter.setInsertionPointToStart(forOp.getBody());
    Value iv = forOp.getInductionVar();
    Value qubit = tensor::ExtractOp::create(rewriter, loc, qubits, iv);
    Value bit = qref::MeasureOp::create(rewriter, loc, Basis::Z, qubit);
    Value bitI64 = arith::ExtUIOp::create(rewriter, loc, i64Type, bit);
    Value ivI64 = arith::IndexCastOp::create(rewriter, loc, i64Type, iv);
    Value shifted = arith::ShLIOp::create(rewriter, loc, bitI64, ivI64);
    Value packed = arith::OrIOp::create(rewriter, loc, forOp.getRegionIterArg(0), shifted);
    scf::YieldOp::create(rewriter, loc, packed);

    rewriter.replaceOpWithMultiple(op, {forOp.getResult(0), ValueRange()});
    return success();
  }
};

/// Converts `jasp.reset` into `qref.reset z`. On an array, resets each qubit in an `scf.for`.
struct ResetConversion final : OpConversionPattern<jasp::ResetOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::ResetOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    const Location loc = op.getLoc();
    Value qubits = adaptor.getQubits();

    if (!isQubitArray(qubits.getType())) {
      qref::ResetOp::create(rewriter, loc, Basis::Z, qubits);
      rewriter.eraseOp(op);
      return success();
    }

    Value c0Index = arith::ConstantIndexOp::create(rewriter, loc, 0);
    Value c1Index = arith::ConstantIndexOp::create(rewriter, loc, 1);
    Value size = tensor::DimOp::create(rewriter, loc, qubits, c0Index);
    auto forOp = scf::ForOp::create(rewriter, loc, c0Index, size, c1Index);

    rewriter.setInsertionPointToStart(forOp.getBody());
    Value qubit = tensor::ExtractOp::create(rewriter, loc, qubits, forOp.getInductionVar());
    qref::ResetOp::create(rewriter, loc, Basis::Z, qubit);

    rewriter.setInsertionPointAfter(forOp);
    rewriter.eraseOp(op);
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Pass
//===----------------------------------------------------------------------===//

struct ConvertJaspToQRef final : impl::ConvertJaspToQRefBase<ConvertJaspToQRef> {
  using ConvertJaspToQRefBase::ConvertJaspToQRefBase;

protected:
  void runOnOperation() override {
    ModuleOp module = getOperation();
    if (failed(checkPreconditions(module, getArgument()))) {
      return signalPassFailure();
    }

    MLIRContext* ctx = &getContext();
    const JaspToQRefTypeConverter typeConverter(ctx);
    const QuantumStateEliminator stateEliminator(ctx);

    ConversionTarget target(*ctx);
    target.addIllegalDialect<jasp::JaspDialect>();
    target.addLegalDialect<QccDialect, qref::QRefDialect, arith::ArithDialect, func::FuncDialect, scf::SCFDialect,
                           tensor::TensorDialect>();

    RewritePatternSet patterns(ctx);
    patterns
        .add<CreateQuantumKernelConversion, ConsumeQuantumKernelConversion, CreateQubitsConversion, GetQubitConversion,
             GetSizeConversion, DeleteQubitsConversion, QuantumGateConversion, MeasureConversion, ResetConversion>(
            typeConverter, ctx);

    populateAnyFunctionOpInterfaceTypeConversionPattern(patterns, stateEliminator);
    target.addDynamicallyLegalOp<func::FuncOp>(
        [&](func::FuncOp op) { return stateEliminator.isSignatureLegal(op.getFunctionType()); });

    populateReturnOpTypeConversionPattern(patterns, stateEliminator);
    target.addDynamicallyLegalOp<func::ReturnOp>([&](func::ReturnOp op) { return stateEliminator.isLegal(op); });

    populateCallOpTypeConversionPattern(patterns, stateEliminator);
    target.addDynamicallyLegalOp<func::CallOp>([&](func::CallOp op) { return stateEliminator.isLegal(op); });

    populateBranchOpInterfaceTypeConversionPattern(patterns, stateEliminator);

    scf::populateSCFStructuralTypeConversionsAndLegality(stateEliminator, patterns, target);

    if (failed(applyPartialConversion(module, target, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
