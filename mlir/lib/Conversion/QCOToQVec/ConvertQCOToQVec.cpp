// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVec.h"

#include "mlir/Dialect/QCO/IR/QCODialect.h"
#include "mlir/Dialect/QCO/IR/QCOOps.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/Block.h"
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

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h"

#include <cstdint>
#include <optional>

using namespace mlir;
using namespace qcc::qvec;

/// Packs `elements` into a vector and returns corresponding `vector.from_elements` op. Used for the qubits as well as
/// for the angle, which `qvec` wants lane-aligned with the qubits: a `vector<1xf64>` here.
static vector::FromElementsOp buildVector(OpBuilder& builder, Location loc, ValueRange elements) {
  auto vectorType = VectorType::get({static_cast<int64_t>(elements.size())}, elements.front().getType());
  return vector::FromElementsOp::create(builder, loc, vectorType, elements);
}

/// Replaces `op` by a one-element `qvec.single` of kind `gate` on `qubit`, with the optional angle `theta`.
static void replaceWithSingle(ConversionPatternRewriter& rewriter, Operation* op, SingleGateKind gate, Value qubit,
                              Value theta = {}) {
  Location loc = op->getLoc();
  Value qubits = buildVector(rewriter, loc, qubit);
  SmallVector<Value, 1> params;
  if (theta) {
    params.push_back(buildVector(rewriter, loc, theta));
  }
  auto singleOp = SingleOp::create(rewriter, loc, gate, qubits, params);
  rewriter.replaceOp(op, vector::ExtractOp::create(rewriter, loc, singleOp.getQubitsOut(), 0));
}

/// Replaces `op` by a one-element `qvec.pair` of kind `gate` on `lhs`, `rhs`, with the optional angle `theta`.
static void replaceWithPair(ConversionPatternRewriter& rewriter, Operation* op, PairGateKind gate, Value lhs, Value rhs,
                            Value theta = {}) {
  Location loc = op->getLoc();
  Value lhsVector = buildVector(rewriter, loc, lhs);
  Value rhsVector = buildVector(rewriter, loc, rhs);
  SmallVector<Value, 1> params;
  if (theta) {
    params.push_back(buildVector(rewriter, loc, theta));
  }
  auto pairOp = PairOp::create(rewriter, loc, gate, lhsVector, rhsVector, params);
  rewriter.replaceOp(op, ValueRange{
                             vector::ExtractOp::create(rewriter, loc, pairOp.getLhsOut(), 0),
                             vector::ExtractOp::create(rewriter, loc, pairOp.getRhsOut(), 0),
                         });
}

namespace {

/// Rewrites a parameter-free single-qubit `qco` gate into a one-element `qvec.single`.
template <typename SourceOp, SingleGateKind gate>
struct SingleGateLowering final : public OpConversionPattern<SourceOp> {
  using OpConversionPattern<SourceOp>::OpConversionPattern;
  using OpAdaptor = SourceOp::Adaptor;

  LogicalResult matchAndRewrite(SourceOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    replaceWithSingle(rewriter, op, gate, adaptor.getQubitIn());
    return success();
  }
};

/// Rewrites a one-angle single-qubit `qco` gate into a one-element `qvec.single`. `qco.p(theta)` becomes `rz(theta)`,
/// which is the same gate up to a global phase.
template <typename SourceOp, SingleGateKind gate> struct RotationLowering final : public OpConversionPattern<SourceOp> {
  using OpConversionPattern<SourceOp>::OpConversionPattern;
  using OpAdaptor = SourceOp::Adaptor;

  LogicalResult matchAndRewrite(SourceOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    replaceWithSingle(rewriter, op, gate, adaptor.getQubitIn(), adaptor.getTheta());
    return success();
  }
};

/// Rewrites `qco.iswap` into a one-element `qvec.pair iswap`.
struct ISwapLowering final : public OpConversionPattern<qco::iSWAPOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qco::iSWAPOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    replaceWithPair(rewriter, op, PairGateKind::iSWAP, adaptor.getQubit0In(), adaptor.getQubit1In());
    return success();
  }
};

/// Rewrites `qco.rzz(theta)` into a one-element `qvec.pair rzz(theta)`.
struct RzzLowering final : public OpConversionPattern<qco::RZZOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qco::RZZOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    replaceWithPair(rewriter, op, PairGateKind::RZZ, adaptor.getQubit0In(), adaptor.getQubit1In(), adaptor.getTheta());
    return success();
  }
};

/// Erases a top-level `qco.gphase`: `qvec` does not model a global phase.
struct GPhaseLowering final : public OpConversionPattern<qco::GPhaseOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qco::GPhaseOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    // Inside a `qco.ctrl` body the phase is relative (a controlled phase); that case is `CtrlLowering`'s and must not
    // be dropped here.
    if (op->getParentOfType<qco::CtrlOp>()) {
      return failure();
    }
    rewriter.eraseOp(op);
    return success();
  }
};

} // namespace

/// Returns the single operation in the body of `op` (besides the terminator), or null if there is more than one.
static Operation* getSingleBodyOp(qco::CtrlOp op) {
  Block& body = op.getRegion().front();
  return body.getOperations().size() == 2 ? &body.front() : nullptr;
}

namespace {

/// Rewrites a singly-controlled gate into a one-element `qvec.pair` (or `qvec.single` for a controlled global phase).
///
/// Only *exact* identities are used here, never "equal up to a global phase": a phase inside a control region is
/// relative and hence observable. The shapes that map are
///   `ctrl(%c) targets(%t) { x | y | z | p(theta) }` -> `pair cx | cy | cz | cp(theta)` and
///   `ctrl(%c) targets() { gphase(theta) }`          -> `single rz(theta)` on the control (it is `p(theta)`, and
///                                                      the phase difference to `rz` is global at this point).
/// Everything else (several controls or targets, `rz` in the body, nested modifiers, ...) is left alone and thus
/// fails legalization.
struct CtrlLowering final : public OpConversionPattern<qco::CtrlOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qco::CtrlOp op, OpAdaptor adaptor, ConversionPatternRewriter& rewriter) const override {
    if (op.getNumControls() != 1) {
      return failure();
    }
    Operation* bodyOp = getSingleBodyOp(op);
    if (bodyOp == nullptr) {
      return failure();
    }
    Value control = adaptor.getControlsIn().front();

    if (op.getNumTargets() == 0) {
      auto gphaseOp = dyn_cast<qco::GPhaseOp>(bodyOp);
      if (!gphaseOp) {
        return failure();
      }
      // The angle is a classical value captured from outside the region, so it is safe to use here.
      replaceWithSingle(rewriter, op, SingleGateKind::RZ, control, gphaseOp.getTheta());
      return success();
    }

    if (op.getNumTargets() != 1) {
      return failure();
    }
    Value target = adaptor.getTargetsIn().front();
    return TypeSwitch<Operation*, LogicalResult>(bodyOp)
        .Case([&](qco::XOp) {
          replaceWithPair(rewriter, op, PairGateKind::CX, control, target);
          return success();
        })
        .Case([&](qco::YOp) {
          replaceWithPair(rewriter, op, PairGateKind::CY, control, target);
          return success();
        })
        .Case([&](qco::ZOp) {
          replaceWithPair(rewriter, op, PairGateKind::CZ, control, target);
          return success();
        })
        .Case([&](qco::POp pOp) {
          replaceWithPair(rewriter, op, PairGateKind::CP, control, target, pOp.getTheta());
          return success();
        })
        .Default([](Operation*) { return failure(); });
  }
};

/// Erases `qco.sink`.
struct SinkLowering final : public OpConversionPattern<qco::SinkOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qco::SinkOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    rewriter.eraseOp(op);
    return success();
  }
};

/// Rewrites `qco.measure` into a one-element `qvec.mz`.
struct MeasureLowering final : public OpConversionPattern<qco::MeasureOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qco::MeasureOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    Location loc = op.getLoc();
    Value qubits = buildVector(rewriter, loc, adaptor.getQubitIn());
    auto bitsType = VectorType::get({1}, rewriter.getI1Type());
    auto mzOp = MzOp::create(rewriter, loc, qubits.getType(), bitsType, qubits);

    rewriter.replaceOp(op, ValueRange{
                               vector::ExtractOp::create(rewriter, loc, mzOp.getQubitsOut(), 0),
                               vector::ExtractOp::create(rewriter, loc, mzOp.getBits(), 0),
                           });
    return success();
  }
};

} // namespace

namespace qcc {

#define GEN_PASS_DEF_CONVERTQCOTOQVEC
#include "qcc/Conversion/QCOToQVec/QCOToQVec.h.inc"

namespace {

struct ConvertQCOToQVec final : impl::ConvertQCOToQVecBase<ConvertQCOToQVec> {
  using ConvertQCOToQVecBase::ConvertQCOToQVecBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();

    ConversionTarget target(*ctx);
    target.addLegalDialect<QVecDialect, vector::VectorDialect>();
    target.addIllegalDialect<qco::QCODialect>();
    target.addLegalOp<qco::StaticOp>(); // still needed as qubit source

    RewritePatternSet patterns(ctx);
    patterns.add<SingleGateLowering<qco::IdOp, SingleGateKind::I>,    //
                 SingleGateLowering<qco::HOp, SingleGateKind::H>,     //
                 SingleGateLowering<qco::XOp, SingleGateKind::X>,     //
                 SingleGateLowering<qco::YOp, SingleGateKind::Y>,     //
                 SingleGateLowering<qco::ZOp, SingleGateKind::Z>,     //
                 SingleGateLowering<qco::SOp, SingleGateKind::S>,     //
                 SingleGateLowering<qco::SdgOp, SingleGateKind::Sdg>, //
                 SingleGateLowering<qco::TOp, SingleGateKind::T>,     //
                 SingleGateLowering<qco::TdgOp, SingleGateKind::Tdg>, //
                 RotationLowering<qco::RXOp, SingleGateKind::RX>,     //
                 RotationLowering<qco::RYOp, SingleGateKind::RY>,     //
                 RotationLowering<qco::RZOp, SingleGateKind::RZ>,     //
                 RotationLowering<qco::POp, SingleGateKind::RZ>,      //
                 ISwapLowering, RzzLowering, GPhaseLowering, CtrlLowering, MeasureLowering, SinkLowering>(ctx);

    if (failed(applyPartialConversion(moduleOp, target, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
