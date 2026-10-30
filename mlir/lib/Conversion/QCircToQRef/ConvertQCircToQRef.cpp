// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/QCircToQRef/QCircToQRef.h" // IWYU pragma: keep
#include "qcc/Dialect/QCF/IR/QCF.h"
#include "qcc/Dialect/QCirc/IR/QCirc.h"
#include "qcc/Dialect/QRef/IR/QRef.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Support/LLVM.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <utility>

namespace qcc {

#define GEN_PASS_DEF_CONVERTQCIRCTOQREF
#include "qcc/Conversion/QCircToQRef/QCircToQRef.h.inc"

using namespace mlir;

namespace {

/// Converts `!qcc.qubit` into `!qcc.qubit_ref` and leaves every other type alone.
struct QCircToQRefTypeConverter final : TypeConverter {
  explicit QCircToQRefTypeConverter(MLIRContext* ctx) {
    addConversion([](Type type) { return type; });
    addConversion([ctx](QubitType /*type*/) { return QubitRefType::get(ctx); });
  }
};

/// Converts `qcc.static` into `qcc.static_ref` with the same indices.
struct StaticConversion final : OpConversionPattern<StaticOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(StaticOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    rewriter.replaceOpWithNewOp<StaticRefOp>(op, op.getIndices());
    return success();
  }
};

/// Converts `qcirc.single` into `qref.single`. Its qubit result is the reference it acts on.
struct SingleConversion final : OpConversionPattern<qcirc::SingleOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qcirc::SingleOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    qref::SingleOp::create(rewriter, op.getLoc(), op.getGateKind(), adaptor.getQubitIn(), adaptor.getParams());
    rewriter.replaceOp(op, adaptor.getQubitIn());
    return success();
  }
};

/// Converts `qcirc.pair` into `qref.pair`. Its qubit results are the references it acts on.
struct PairConversion final : OpConversionPattern<qcirc::PairOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qcirc::PairOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    qref::PairOp::create(rewriter, op.getLoc(), op.getGateKind(), adaptor.getLhsIn(), adaptor.getRhsIn(),
                         adaptor.getParams());
    rewriter.replaceOp(op, ValueRange{adaptor.getLhsIn(), adaptor.getRhsIn()});
    return success();
  }
};

/// Converts `qcirc.measure` into `qref.measure`. Its qubit result is the reference it acts on.
struct MeasureConversion final : OpConversionPattern<qcirc::MeasureOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qcirc::MeasureOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    auto measure = qref::MeasureOp::create(rewriter, op.getLoc(), op.getBasis(), adaptor.getQubitIn());
    rewriter.replaceOp(op, ValueRange{adaptor.getQubitIn(), measure.getBit()});
    return success();
  }
};

/// Converts `qcirc.reset` into `qref.reset`. Its qubit result is the reference it acts on.
struct ResetConversion final : OpConversionPattern<qcirc::ResetOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qcirc::ResetOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    qref::ResetOp::create(rewriter, op.getLoc(), op.getBasis(), adaptor.getQubitIn());
    rewriter.replaceOp(op, adaptor.getQubitIn());
    return success();
  }
};

/// Converts `qcf.if` into `scf.if` with the classical results only. Its bindings and its qubit results are the bound
/// references. An omitted else region stays omitted.
struct IfConversion final : OpConversionPattern<qcf::IfOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qcf::IfOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    ValueRange qubits = adaptor.getQubitsIn();
    auto ifOp = scf::IfOp::create(rewriter, op.getLoc(), op.getClassicalResults().getTypes(), adaptor.getCondition(),
                                  /*addThenBlock=*/false, /*addElseBlock=*/false);
    for (auto [from, to] : llvm::zip_equal(op->getRegions(), ifOp->getRegions())) {
      if (from.empty()) {
        continue;
      }
      rewriter.inlineRegionBefore(from, to, to.end());
      TypeConverter::SignatureConversion bindings(to.getNumArguments());
      for (auto [binding, qubit] : llvm::zip_equal(to.getArguments(), qubits)) {
        bindings.remapInput(binding.getArgNumber(), qubit);
      }
      rewriter.applySignatureConversion(&to.front(), bindings);
    }

    SmallVector<Value> results(qubits);
    llvm::append_range(results, ifOp.getResults());
    rewriter.replaceOp(op, results);
    return success();
  }
};

/// Converts `qcf.yield` into `scf.yield` of the classical values: references need not be yielded.
struct YieldConversion final : OpConversionPattern<qcf::YieldOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qcf::YieldOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    // `IfConversion` has moved the region into an `scf.if`, whose results are the classical ones.
    auto ifOp = dyn_cast<scf::IfOp>(op->getParentOp());
    if (!ifOp) {
      return failure();
    }
    rewriter.replaceOpWithNewOp<scf::YieldOp>(op, adaptor.getResults().take_back(ifOp.getNumResults()));
    return success();
  }
};

struct ConvertQCircToQRef final : impl::ConvertQCircToQRefBase<ConvertQCircToQRef> {
  using ConvertQCircToQRefBase::ConvertQCircToQRefBase;

protected:
  void runOnOperation() override {
    MLIRContext* ctx = &getContext();

    // Precondition: no vectors of qubits.
    const WalkResult vectors = getOperation()->walk([](Operation* op) {
      auto isQubitVector = [](Type type) { return isa<VectorType>(type) && isQubitOrQubitVector(type); };
      if (llvm::any_of(op->getOperandTypes(), isQubitVector) || llvm::any_of(op->getResultTypes(), isQubitVector)) {
        op->emitOpError() << "is not supported on vectors of qubits";
        return WalkResult::interrupt();
      }
      return WalkResult::advance();
    });
    if (vectors.wasInterrupted()) {
      return signalPassFailure();
    }

    ConversionTarget target(*ctx);
    target.addIllegalDialect<qcirc::QCircDialect, qcf::QCFDialect>();
    target.addIllegalOp<StaticOp>();
    target.addLegalDialect<qref::QRefDialect, scf::SCFDialect>();
    target.addLegalOp<StaticRefOp>();

    const QCircToQRefTypeConverter typeConverter(ctx);
    RewritePatternSet patterns(ctx);
    patterns.add<StaticConversion, SingleConversion, PairConversion, MeasureConversion, ResetConversion, IfConversion,
                 YieldConversion>(typeConverter, ctx);

    if (failed(applyPartialConversion(getOperation(), target, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
