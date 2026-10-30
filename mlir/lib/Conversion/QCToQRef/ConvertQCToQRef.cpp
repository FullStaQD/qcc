// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/QCToQRef/QCToQRef.h" // IWYU pragma: keep
#include "qcc/Dialect/QRef/IR/QRef.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/QC/IR/QCDialect.h"
#include "mlir/Dialect/QC/IR/QCOps.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Support/LLVM.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/TypeSwitch.h"

#include <cstdint>
#include <utility>

namespace qcc {

#define GEN_PASS_DEF_CONVERTQCTOQREF
#include "qcc/Conversion/QCToQRef/QCToQRef.h.inc"

using namespace mlir;

namespace {

/// Converts `!qc.qubit` into `!qcc.qubit_ref` and leaves every other type alone.
struct QCToQRefTypeConverter final : TypeConverter {
  explicit QCToQRefTypeConverter(MLIRContext* ctx) {
    addConversion([](Type type) { return type; });
    addConversion([ctx](qc::QubitType /*type*/) { return QubitRefType::get(ctx); });
  }
};

/// Converts `qc.static N` into `qcc.static_ref [N]`.
struct StaticConversion final : OpConversionPattern<qc::StaticOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qc::StaticOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    const auto index = static_cast<int64_t>(op.getIndex());
    rewriter.replaceOpWithNewOp<StaticRefOp>(op, ArrayRef(index));
    return success();
  }
};

/// Converts a single-qubit gate into `qref.single` of `kind`. The qubit is the first operand, the angles follow.
template <typename SourceOp, SingleGateKind kind> struct SingleConversion final : OpConversionPattern<SourceOp> {
  using OpConversionPattern<SourceOp>::OpConversionPattern;
  using OpAdaptor = SourceOp::Adaptor;

  LogicalResult matchAndRewrite(SourceOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    ValueRange operands = adaptor.getOperands();
    rewriter.replaceOpWithNewOp<qref::SingleOp>(op, kind, operands.front(), operands.drop_front());
    return success();
  }
};

/// Converts a two-qubit gate into `qref.pair` of `kind`. The qubits are the first two operands, the angles follow.
template <typename SourceOp, PairGateKind kind> struct PairConversion final : OpConversionPattern<SourceOp> {
  using OpConversionPattern<SourceOp>::OpConversionPattern;
  using OpAdaptor = SourceOp::Adaptor;

  LogicalResult matchAndRewrite(SourceOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    ValueRange operands = adaptor.getOperands();
    rewriter.replaceOpWithNewOp<qref::PairOp>(op, kind, operands[0], operands[1], operands.drop_front(2));
    return success();
  }
};

/// Converts `qc.u(theta, phi, lambda)` into `qref.single u_zyz(lambda, theta, phi)`: both are
/// `rz(phi) * ry(theta) * rz(lambda)` up to a global phase.
struct UConversion final : OpConversionPattern<qc::UOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qc::UOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    rewriter.replaceOpWithNewOp<qref::SingleOp>(op, SingleGateKind::UZYZ, adaptor.getQubitIn(),
                                                ValueRange{adaptor.getLambda(), adaptor.getTheta(), adaptor.getPhi()});
    return success();
  }
};

/// Erases a gate that has no effect up to a global phase: `qc.id`, and `qc.gphase` outside a control.
template <typename SourceOp> struct DropConversion final : OpConversionPattern<SourceOp> {
  using OpConversionPattern<SourceOp>::OpConversionPattern;
  using OpAdaptor = SourceOp::Adaptor;

  LogicalResult matchAndRewrite(SourceOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    // Under a control, a phase is relative. `CtrlConversion` replaces the whole `qc.ctrl` instead.
    if (op->template getParentOfType<qc::CtrlOp>()) {
      return failure();
    }
    rewriter.eraseOp(op);
    return success();
  }
};

/// Converts `qc.ctrl` with one control around a single gate into a two-qubit gate:
///   `ctrl(%c) targets(%t) { x | y | z | p(theta) | rz(theta) }` -> `pair cx | cy | cz | cp(theta) | crz(theta)` and
///   `ctrl(%c) targets() { gphase(theta) }`                      -> `single rz(theta)` on the control.
/// The second one is `p(theta)` on the control, which is `rz(theta)` up to a global phase. Anything else fails.
struct CtrlConversion final : OpConversionPattern<qc::CtrlOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qc::CtrlOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    Block& body = *op.getBody();
    if (op.getNumControls() != 1 || op.getNumTargets() > 1 || !llvm::hasNItems(body, 2)) {
      return failure();
    }
    Operation* gate = &body.front();
    Value control = adaptor.getControls().front();

    // The angles are classical values from outside the region, so they stay valid when it is erased.
    if (op.getNumTargets() == 0) {
      auto gphase = dyn_cast<qc::GPhaseOp>(gate);
      if (!gphase) {
        return failure();
      }
      rewriter.replaceOpWithNewOp<qref::SingleOp>(op, SingleGateKind::RZ, control, gphase.getTheta());
      return success();
    }

    Value target = adaptor.getTargets().front();
    auto replaceWithPair = [&](PairGateKind kind, ValueRange params = {}) {
      rewriter.replaceOpWithNewOp<qref::PairOp>(op, kind, control, target, params);
      return success();
    };
    return llvm::TypeSwitch<Operation*, LogicalResult>(gate)
        .Case([&](qc::XOp) { return replaceWithPair(PairGateKind::CX); })
        .Case([&](qc::YOp) { return replaceWithPair(PairGateKind::CY); })
        .Case([&](qc::ZOp) { return replaceWithPair(PairGateKind::CZ); })
        .Case([&](qc::POp p) { return replaceWithPair(PairGateKind::CP, p.getTheta()); })
        .Case([&](qc::RZOp rz) { return replaceWithPair(PairGateKind::CRZ, rz.getTheta()); })
        .Default([](Operation*) { return failure(); });
  }
};

/// Converts `qc.measure` into `qref.measure z`.
struct MeasureConversion final : OpConversionPattern<qc::MeasureOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qc::MeasureOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    rewriter.replaceOpWithNewOp<qref::MeasureOp>(op, Basis::Z, adaptor.getQubit());
    return success();
  }
};

/// Converts `qc.reset` into `qref.reset z`.
struct ResetConversion final : OpConversionPattern<qc::ResetOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qc::ResetOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    rewriter.replaceOpWithNewOp<qref::ResetOp>(op, Basis::Z, adaptor.getQubit());
    return success();
  }
};

struct ConvertQCToQRef final : impl::ConvertQCToQRefBase<ConvertQCToQRef> {
  using ConvertQCToQRefBase::ConvertQCToQRefBase;

protected:
  void runOnOperation() override {
    MLIRContext* ctx = &getContext();

    ConversionTarget target(*ctx);
    target.addIllegalDialect<qc::QCDialect>();
    target.addLegalDialect<QccDialect, qref::QRefDialect>();

    const QCToQRefTypeConverter typeConverter(ctx);
    RewritePatternSet patterns(ctx);
    patterns.add<StaticConversion,                                   //
                 SingleConversion<qc::XOp, SingleGateKind::X>,       //
                 SingleConversion<qc::YOp, SingleGateKind::Y>,       //
                 SingleConversion<qc::ZOp, SingleGateKind::Z>,       //
                 SingleConversion<qc::HOp, SingleGateKind::H>,       //
                 SingleConversion<qc::SOp, SingleGateKind::S>,       //
                 SingleConversion<qc::SdgOp, SingleGateKind::Sdg>,   //
                 SingleConversion<qc::TOp, SingleGateKind::T>,       //
                 SingleConversion<qc::TdgOp, SingleGateKind::Tdg>,   //
                 SingleConversion<qc::SXOp, SingleGateKind::SX>,     //
                 SingleConversion<qc::SXdgOp, SingleGateKind::SXdg>, //
                 SingleConversion<qc::RXOp, SingleGateKind::RX>,     //
                 SingleConversion<qc::RYOp, SingleGateKind::RY>,     //
                 SingleConversion<qc::RZOp, SingleGateKind::RZ>,     //
                 SingleConversion<qc::POp, SingleGateKind::RZ>,      //
                 PairConversion<qc::SWAPOp, PairGateKind::SWAP>,     //
                 PairConversion<qc::iSWAPOp, PairGateKind::iSWAP>,   //
                 PairConversion<qc::RXXOp, PairGateKind::RXX>,       //
                 PairConversion<qc::RYYOp, PairGateKind::RYY>,       //
                 PairConversion<qc::RZZOp, PairGateKind::RZZ>,       //
                 DropConversion<qc::IdOp>,                           //
                 DropConversion<qc::GPhaseOp>,                       //
                 UConversion, CtrlConversion, MeasureConversion, ResetConversion>(typeConverter, ctx);

    if (failed(applyPartialConversion(getOperation(), target, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
