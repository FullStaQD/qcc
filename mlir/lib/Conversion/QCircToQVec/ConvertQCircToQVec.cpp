// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/QCircToQVec/QCircToQVec.h" // IWYU pragma: keep
#include "qcc/Dialect/QCF/IR/QCF.h"
#include "qcc/Dialect/QCirc/IR/QCirc.h"
#include "qcc/Dialect/QVec/IR/QVec.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/Func/IR/FuncOps.h" // IWYU pragma: keep
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Location.h"
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
#include "llvm/ADT/SmallVector.h" // IWYU pragma: keep
#include "llvm/ADT/SmallVectorExtras.h"

#include <utility>

namespace qcc {

#define GEN_PASS_DEF_CONVERTQCIRCTOQVEC
#include "qcc/Conversion/QCircToQVec/QCircToQVec.h.inc"

using namespace mlir;

/// Whether an operand or a result of `op` has a type that satisfies `predicate`.
static bool holds(Operation* op, function_ref<bool(Type)> predicate) {
  return llvm::any_of(op->getOperandTypes(), predicate) || llvm::any_of(op->getResultTypes(), predicate);
}

/// Packs `element` into a vector of one element.
static Value buildVector(OpBuilder& builder, Location loc, Value element) {
  return vector::FromElementsOp::create(builder, loc, VectorType::get({1}, element.getType()), element);
}

/// Packs each angle of `params` into a vector of one element: `qvec` wants its angles lane-aligned with the qubits.
static SmallVector<Value> buildAngleVectors(OpBuilder& builder, Location loc, ValueRange params) {
  return llvm::map_to_vector(params, [&](Value param) { return buildVector(builder, loc, param); });
}

namespace {

/// Converts `!qcc.qubit` into `vector<1x!qcc.qubit>`. The `qcc.static` op still produces `!qcc.qubit` after the
/// conversion. We use `vector.from_elements` as target materialization to pack it into a vector.
struct QCircToQVecTypeConverter final : TypeConverter {
  QCircToQVecTypeConverter() {
    addConversion([](Type type) { return type; });
    addConversion([](QubitType type) { return VectorType::get({1}, type); });
    addTargetMaterialization([](OpBuilder& builder, VectorType type, ValueRange inputs, Location loc) -> Value {
      if (inputs.size() != 1 || !isa<QubitType>(inputs.front().getType())) {
        return {};
      }
      return vector::FromElementsOp::create(builder, loc, type, inputs);
    });
  }
};

/// Converts `qcirc.single` into `qvec.single`.
struct SingleConversion final : OpConversionPattern<qcirc::SingleOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qcirc::SingleOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    SmallVector<Value> params = buildAngleVectors(rewriter, op.getLoc(), adaptor.getParams());
    rewriter.replaceOpWithNewOp<qvec::SingleOp>(op, op.getGateKind(), adaptor.getQubitIn(), params);
    return success();
  }
};

/// Converts `qcirc.pair` into `qvec.pair`.
struct PairConversion final : OpConversionPattern<qcirc::PairOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qcirc::PairOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    SmallVector<Value> params = buildAngleVectors(rewriter, op.getLoc(), adaptor.getParams());
    rewriter.replaceOpWithNewOp<qvec::PairOp>(op, op.getGateKind(), adaptor.getLhsIn(), adaptor.getRhsIn(), params);
    return success();
  }
};

/// Converts `qcirc.measure` into `qvec.measure`.
struct MeasureConversion final : OpConversionPattern<qcirc::MeasureOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qcirc::MeasureOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    Location loc = op.getLoc();
    auto measure = qvec::MeasureOp::create(rewriter, loc, op.getBasis(), adaptor.getQubitIn());
    Value bit = vector::ExtractOp::create(rewriter, loc, measure.getBits(), 0);
    rewriter.replaceOp(op, ValueRange{measure.getQubitsOut(), bit});
    return success();
  }
};

/// Converts `qcirc.reset` into `qvec.reset`.
struct ResetConversion final : OpConversionPattern<qcirc::ResetOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qcirc::ResetOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    rewriter.replaceOpWithNewOp<qvec::ResetOp>(op, op.getBasis(), adaptor.getQubitIn());
    return success();
  }
};

/// Converts the qubits of `qcf.if` into vectors: its bindings, the arguments of its regions and its qubit results.
struct IfConversion final : OpConversionPattern<qcf::IfOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qcf::IfOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    auto ifOp = qcf::IfOp::create(rewriter, op.getLoc(), adaptor.getCondition(), adaptor.getQubitsIn(),
                                  op.getClassicalResults().getTypes(), /*addThenBlock=*/false,
                                  /*addElseBlock=*/false);
    for (auto [from, to] : llvm::zip_equal(op->getRegions(), ifOp->getRegions())) {
      rewriter.inlineRegionBefore(from, to, to.end());
      if (failed(rewriter.convertRegionTypes(&to, *getTypeConverter()))) {
        return failure();
      }
    }
    rewriter.replaceOp(op, ifOp.getResults());
    return success();
  }
};

/// Converts the qubits `qcf.yield` passes on into vectors.
struct YieldConversion final : OpConversionPattern<qcf::YieldOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qcf::YieldOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    rewriter.replaceOpWithNewOp<qcf::YieldOp>(op, adaptor.getResults());
    return success();
  }
};

struct ConvertQCircToQVec final : impl::ConvertQCircToQVecBase<ConvertQCircToQVec> {
  using ConvertQCircToQVecBase::ConvertQCircToQVecBase;

protected:
  void runOnOperation() override {
    MLIRContext* ctx = &getContext();

    // Check the precondition: only ops from a whitelist use qubits.
    const WalkResult unsupported = getOperation()->walk<WalkOrder::PreOrder>([&](Operation* op) {
      if (!isa<StaticOp>(op) && !isa_and_present<qcirc::QCircDialect, qcf::QCFDialect>(op->getDialect()) &&
          holds(op, isQubitOrQubitVector)) {
        op->emitOpError() << "uses qubits, but " << getArgument()
                          << " expects only 'qcc.static', 'qcirc' and 'qcf' ops to use qubits";
        return WalkResult::interrupt();
      }
      return WalkResult::advance();
    });
    if (unsupported.wasInterrupted()) {
      return signalPassFailure();
    }

    const QCircToQVecTypeConverter typeConverter;
    ConversionTarget target(*ctx);
    target.addIllegalDialect<qcirc::QCircDialect>();
    target.addDynamicallyLegalDialect<qcf::QCFDialect>([&](Operation* op) { return typeConverter.isLegal(op); });
    target.addLegalDialect<qvec::QVecDialect, vector::VectorDialect>();
    target.addLegalOp<StaticOp>();

    RewritePatternSet patterns(ctx);
    patterns.add<SingleConversion, PairConversion, MeasureConversion, ResetConversion, IfConversion, YieldConversion>(
        typeConverter, ctx);

    if (failed(applyPartialConversion(getOperation(), target, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
