// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/HiSEPQ/IR/HiSEPQ.h"

#include "mlir/Dialect/QCO/IR/QCODialect.h"
#include "mlir/Dialect/QCO/IR/QCOOps.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LogicalResult.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/TypeSwitch.h"

#include <cstdint>
#include <optional>

using namespace mlir;
using namespace qcc::hisepq;

namespace {

/// Packs `elements` into a qubit vector and returns corresponding `vector.from_elements` op.
vector::FromElementsOp buildQubitVector(OpBuilder& builder, Location loc, ValueRange elements) {
  auto vectorType = VectorType::get({static_cast<int64_t>(elements.size())}, elements.front().getType());
  return vector::FromElementsOp::create(builder, loc, vectorType, elements);
}

/// Rewrites a single-qubit `qco` gate into a one-element `hisepq.single`.
template <typename SourceOp, SingleGate gate> struct SingleGateLowering final : public OpConversionPattern<SourceOp> {
  using OpConversionPattern<SourceOp>::OpConversionPattern;
  using OpAdaptor = typename SourceOp::Adaptor;

  LogicalResult matchAndRewrite(SourceOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    Location loc = op.getLoc();
    Value qubits = buildQubitVector(rewriter, loc, adaptor.getQubitIn());
    auto singleOp = SingleOp::create(rewriter, loc, qubits.getType(), gate, qubits);

    rewriter.replaceOp(op, vector::ExtractOp::create(rewriter, loc, singleOp.getQubitsOut(), 0));
    return success();
  }
};

/// Rewrites `qco.iswap` into a one-element `hisepq.pair iswap`.
struct ISwapLowering final : public OpConversionPattern<qco::iSWAPOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qco::iSWAPOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    Location loc = op.getLoc();
    Value v0 = buildQubitVector(rewriter, loc, adaptor.getQubit0In());
    Value v1 = buildQubitVector(rewriter, loc, adaptor.getQubit1In());
    auto pairOp = PairOp::create(rewriter, loc, v0.getType(), v1.getType(), PairGate::iSWAP, v0, v1);

    rewriter.replaceOp(op, ValueRange{vector::ExtractOp::create(rewriter, loc, pairOp.getCtrlsOut(), 0),
                                      vector::ExtractOp::create(rewriter, loc, pairOp.getTgtsOut(), 0)});
    return success();
  }
};

/// Returns the pair gate a `qco.ctrl` body denotes, or nullopt if it denotes none.
///
/// Only the shape `ctrl(%c) targets(%t) { qco.SINGLE_QUBIT_GATE }` maps.
std::optional<PairGate> getControlledPairGate(qco::CtrlOp op) {
  if (op.getNumControls() != 1 || op.getNumTargets() != 1) {
    return std::nullopt;
  }

  // The body holds the unitary plus the `qco.yield` terminator.
  Block& body = op.getRegion().front();
  if (body.getOperations().size() != 2) {
    return std::nullopt;
  }

  return TypeSwitch<Operation*, std::optional<PairGate>>(&body.front())
      .Case([](qco::XOp) { return PairGate::CX; })
      .Case([](qco::YOp) { return PairGate::CY; })
      .Case([](qco::ZOp) { return PairGate::CZ; })
      .Default([](Operation*) { return std::nullopt; });
}

/// Rewrites a singly-controlled single-target gate into a one-element `hisepq.pair`.
struct CtrlLowering final : public OpConversionPattern<qco::CtrlOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qco::CtrlOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    std::optional<PairGate> gate = getControlledPairGate(op);
    if (!gate) {
      return failure();
    }

    Location loc = op.getLoc();
    Value ctrls = buildQubitVector(rewriter, loc, adaptor.getControlsIn().front());
    Value tgts = buildQubitVector(rewriter, loc, adaptor.getTargetsIn().front());
    auto pairOp = PairOp::create(rewriter, loc, ctrls.getType(), tgts.getType(), *gate, ctrls, tgts);

    rewriter.replaceOp(op, ValueRange{vector::ExtractOp::create(rewriter, loc, pairOp.getCtrlsOut(), 0),
                                      vector::ExtractOp::create(rewriter, loc, pairOp.getTgtsOut(), 0)});
    return success();
  }
};

/// Rewrites `qco.measure` into a one-element `hisepq.mz`.
struct MeasureLowering final : public OpConversionPattern<qco::MeasureOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qco::MeasureOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    Location loc = op.getLoc();
    Value qubits = buildQubitVector(rewriter, loc, adaptor.getQubitIn());
    auto bitsType = VectorType::get({1}, rewriter.getI1Type());
    auto mzOp = MzOp::create(rewriter, loc, qubits.getType(), bitsType, qubits);

    rewriter.replaceOp(op, ValueRange{vector::ExtractOp::create(rewriter, loc, mzOp.getQubitsOut(), 0),
                                      vector::ExtractOp::create(rewriter, loc, mzOp.getBits(), 0)});
    return success();
  }
};

bool isInsideCtrlBody(Operation* op) { return isa_and_present<qco::CtrlOp>(op->getParentOp()); }

} // namespace

namespace qcc {

#define GEN_PASS_DEF_CONVERTQCOTOHISEPQ
#include "qcc/Conversion/ToHiSEPQ/ToHiSEPQ.h.inc"

namespace {

struct ConvertQCOToHiSEPQ final : impl::ConvertQCOToHiSEPQBase<ConvertQCOToHiSEPQ> {
  using ConvertQCOToHiSEPQBase::ConvertQCOToHiSEPQBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();

    ConversionTarget target(*ctx);
    target.addLegalDialect<HiSEPQDialect, vector::VectorDialect>();
    target.addIllegalDialect<qco::QCODialect>();
    target.addLegalOp<qco::StaticOp>(); // still needed as qubit source

    // FIXME: Why? Is this even correct?
    target.addDynamicallyLegalOp<qco::XOp, qco::YOp, qco::ZOp, qco::YieldOp>(isInsideCtrlBody);

    RewritePatternSet patterns(ctx);
    patterns.add<SingleGateLowering<qco::IdOp, SingleGate::I>,    //
                 SingleGateLowering<qco::HOp, SingleGate::H>,     //
                 SingleGateLowering<qco::XOp, SingleGate::X>,     //
                 SingleGateLowering<qco::YOp, SingleGate::Y>,     //
                 SingleGateLowering<qco::ZOp, SingleGate::Z>,     //
                 SingleGateLowering<qco::SOp, SingleGate::S>,     //
                 SingleGateLowering<qco::SdgOp, SingleGate::Sdg>, //
                 SingleGateLowering<qco::TOp, SingleGate::T>,     //
                 SingleGateLowering<qco::TdgOp, SingleGate::Tdg>, //
                 ISwapLowering, CtrlLowering, MeasureLowering>(ctx);

    if (failed(applyPartialConversion(moduleOp, target, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
