// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/ToHiSEPQ/HiSEPQMachine.h"
#include "qcc/Conversion/ToHiSEPQ/ToHiSEPQ.h" // IWYU pragma: keep
#include "qcc/Dialect/Aux_/IR/Aux_.h"
#include "qcc/Dialect/QCF/IR/QCF.h"
#include "qcc/Dialect/QVec/IR/QVec.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Value.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LogicalResult.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <optional>
#include <utility>

using namespace mlir;
using namespace qcc::qvec;
using qcc::PairGateKind;
using qcc::SingleGateKind;
using qcc::hisepq::HiSEPQMachine;

namespace {

/// A qubit vector operand reduced to what the intrinsic needs from it.
struct ResolvedQubits {
  /// One static qubit index per vector element.
  SmallVector<int64_t> indices;
  /// The scalable `vector<[N] x i{QEW}>` type the indices have to be handed over in.
  VectorType qvType;
};

/// Shared state of the lowering patterns: the diagnostics they emit.
struct Diagnostics {
  bool hadError = false;

  /// Emits `message` on `op` and marks the pass as failed.
  LogicalResult report(Operation* op, const Twine& message) {
    op->emitOpError(message);
    hadError = true;
    return failure();
  }
};

} // namespace

/// Reads the qubit indices out of a vector by tracing every element to its `qcc.static`.
static std::optional<SmallVector<int64_t>> getQubitIndices(TypedValue<VectorType> qubitVector) {
  SmallVector<int64_t> indices;
  for (int64_t index = 0; index < qubitVector.getType().getNumElements(); ++index) {
    std::optional<int64_t> qubit = getStaticQubitIndex(qubitVector, index);
    if (!qubit) {
      return std::nullopt;
    }
    indices.push_back(*qubit);
  }

  return indices;
}

/// Materializes qubit indices for use as operand of a qv intrinsic.
///
/// The indices become one dense `vector<Nxi{QEW}>` constant, which is then inserted into a poison
/// scalable vector of `qvType`. The poison base is deliberate: the intrinsic is emitted with
/// `vl = N`, so the elements above the last index are never read.
///
/// QEW is read off `qvType`, which the machine picked the indices to fit.
static Value buildQubitVector(OpBuilder& builder, Location loc, const ResolvedQubits& qubits) {
  ArrayRef<int64_t> qubitIndices = qubits.indices;
  VectorType qvType = qubits.qvType;

  Type elementType = qvType.getElementType();
  const unsigned qew = elementType.getIntOrFloatBitWidth();
  auto fixedType = VectorType::get({static_cast<int64_t>(qubitIndices.size())}, elementType);

  SmallVector<APInt> indexValues;
  indexValues.reserve(qubitIndices.size());
  for (int64_t index : qubitIndices) {
    assert(0 <= index && std::cmp_less(index, uint64_t{1} << qew) && "does not fit into QEW bits");
    indexValues.emplace_back(qew, static_cast<uint64_t>(index));
  }

  Value qubitVec = LLVM::ConstantOp::create(builder, loc, fixedType, DenseElementsAttr::get(fixedType, indexValues));
  Value poisonVec = LLVM::PoisonOp::create(builder, loc, qvType);

  return LLVM::vector_insert::create(builder, loc, poisonVec, qubitVec, /*pos=*/0);
}

/// Checks a qubit operand of `op` and works out what the intrinsic needs for it.
///
/// Emits nothing, so that an operation with two qubit operands can have both of them validated
/// before any of them is materialized.
static std::optional<ResolvedQubits> resolveQubitVector(Operation* op, TypedValue<VectorType> qubits,
                                                        const HiSEPQMachine& machine, Diagnostics& diags) {
  auto indices = getQubitIndices(qubits);
  if (!indices) {
    (void)diags.report(op, "expects every qubit vector element to trace back to a 'qcc.static' operation");
    return std::nullopt;
  }

  const unsigned qew = machine.getQubitElementWidth();
  for (int64_t index : *indices) {
    if (std::cmp_greater(index, machine.maxQubitIndex())) {
      (void)diags.report(op, "qubit index " + Twine(index) + " exceeds the maximum of " +
                                 Twine(machine.maxQubitIndex()) + " for " + Twine(machine.getNumQubitControlLines()) +
                                 " qubit control lines");
      return std::nullopt;
    }
  }

  auto numQubits = indices->size();
  auto qvType = machine.qubitVectorType(op->getContext(), static_cast<unsigned>(numQubits));
  if (!qvType) {
    (void)diags.report(op, "has " + Twine(indices->size()) + " qubits, but at a minimum VLEN of " +
                               Twine(machine.getMinVLen()) + " and a qubit element width of " + Twine(qew) +
                               " the QV instructions address at most " + Twine(machine.maxQubits()));
    return std::nullopt;
  }

  return ResolvedQubits{.indices = std::move(*indices), .qvType = *qvType};
}

/// Returns the intrinsic implementing `gate`, or an empty ref if there is none.
static StringRef getSingleGateIntrinsic(SingleGateKind gate) {
  switch (gate) {
  case SingleGateKind::H:
    return "llvm.riscv.qv.h";
  case SingleGateKind::X:
    return "llvm.riscv.qv.x";
  case SingleGateKind::Y:
  case SingleGateKind::Z:
  case SingleGateKind::S:
  case SingleGateKind::Sdg:
  case SingleGateKind::T:
  case SingleGateKind::Tdg:
  case SingleGateKind::SX:
  case SingleGateKind::SXdg:
  case SingleGateKind::RX:
  case SingleGateKind::RY:
  case SingleGateKind::RZ:
  case SingleGateKind::UZXZ:
  case SingleGateKind::UZYZ:
    return {};
  }
  return {};
}

/// Returns the intrinsic implementing `gate`, or an empty ref if there is none.
static StringRef getPairGateIntrinsic(PairGateKind gate) {
  switch (gate) {
  case PairGateKind::CX:
    return "llvm.riscv.qv.cx";
  case PairGateKind::CY:
  case PairGateKind::CZ:
  case PairGateKind::SWAP:
  case PairGateKind::iSWAP:
  case PairGateKind::CP:
  case PairGateKind::CRZ:
  case PairGateKind::RXX:
  case PairGateKind::RYY:
  case PairGateKind::RZZ:
    return {};
  }
  return {};
}

/// Creates the up to three scalar operands every QV intrinsic ends with
/// `intrinsic(..., [tag,] wait_time, num_qubits)`.
///
/// The software tag (`rs2`) and wait time (`block_imm`) set to 0 until the dialect models them.
static SmallVector<Value> buildScalarOperands(OpBuilder& builder, Location loc, unsigned numQubits, bool withTag) {
  auto i32Type = builder.getI32Type();
  auto constant = [&](int32_t value) -> Value {
    return LLVM::ConstantOp::create(builder, loc, i32Type, builder.getI32IntegerAttr(value));
  };

  SmallVector<Value> operands;
  if (withTag) {
    operands.push_back(constant(0)); // tag (rs2)
  }
  operands.push_back(constant(0));                               // wait time (block_imm)
  operands.push_back(constant(static_cast<int32_t>(numQubits))); // number of qubits to access
  return operands;
}

/// Calls the QV `intrinsic` on `qubits`, for the intrinsics with one qubit vector and a tag (single-qubit gates, `mz`).
static void createQubitsIntrinsic(OpBuilder& builder, Location loc, StringRef intrinsic, const ResolvedQubits& qubits) {
  SmallVector<Value> args{buildQubitVector(builder, loc, qubits)};
  llvm::append_range(args, buildScalarOperands(builder, loc, static_cast<unsigned>(qubits.indices.size()),
                                               /*withTag=*/true));
  LLVM::CallIntrinsicOp::create(builder, loc, builder.getStringAttr(intrinsic), args);
}

/// Measures `qubits` in the Z basis and returns one `i1` outcome per qubit.
///
/// The outcomes are read from CSR `qv.mres` right after each `qv.mz`, because the next measurement overwrites them. Bit
/// `k` is the outcome of element `k`. `qv.mres` holds only 32 outcomes, so larger measurements are split into chunks.
static SmallVector<Value> createMeasurement(OpBuilder& builder, Location loc, const ResolvedQubits& qubits,
                                            const HiSEPQMachine& machine) {
  auto i32Type = builder.getI32Type();
  SmallVector<Value> outcomes;
  ArrayRef<int64_t> remaining = qubits.indices;
  while (!remaining.empty()) {
    ArrayRef<int64_t> chunk = remaining.take_front(HiSEPQMachine::maxMeasuredQubits());
    remaining = remaining.drop_front(chunk.size());
    auto numQubits = static_cast<unsigned>(chunk.size());
    // A chunk is never larger than `qubits`, so it fits into a vector too.
    const ResolvedQubits chunkQubits{.indices = llvm::to_vector(chunk),
                                     .qvType = *machine.qubitVectorType(builder.getContext(), numQubits)};
    createQubitsIntrinsic(builder, loc, "llvm.riscv.qv.mz", chunkQubits);

    Value result =
        LLVM::CallIntrinsicOp::create(builder, loc, i32Type, builder.getStringAttr("llvm.riscv.qv.mres"), ValueRange{})
            .getResult(0);
    for (unsigned element = 0; element < numQubits; ++element) {
      Value shift =
          LLVM::ConstantOp::create(builder, loc, i32Type, builder.getI32IntegerAttr(static_cast<int32_t>(element)));
      Value shifted = LLVM::LShrOp::create(builder, loc, result, shift);
      outcomes.push_back(LLVM::TruncOp::create(builder, loc, builder.getI1Type(), shifted));
    }
  }
  return outcomes;
}

namespace {

/// Rewrites `qvec.single` into `llvm.call_intrinsic "llvm.riscv.qv.{h,x,...}"`.
struct SingleOpLowering : public OpRewritePattern<SingleOp> {
  SingleOpLowering(MLIRContext* ctx, Diagnostics* diags, HiSEPQMachine machine)
      : OpRewritePattern(ctx), diags(diags), machine(machine) {}

  LogicalResult matchAndRewrite(SingleOp op, PatternRewriter& rewriter) const override {
    StringRef intrinsic = getSingleGateIntrinsic(op.getGateKind());
    if (intrinsic.empty()) {
      return diags->report(op, "gate '" + stringifySingleGateKind(op.getGateKind()) + "' has no HiSEP-Q intrinsic");
    }

    auto qubits = resolveQubitVector(op, op.getQubitsIn(), machine, *diags);
    if (!qubits) {
      return failure();
    }

    createQubitsIntrinsic(rewriter, op.getLoc(), intrinsic, *qubits);

    // The instruction acts in place, so what comes out is what went in.
    rewriter.replaceOp(op, ValueRange{op.getQubitsIn()});
    return success();
  }

  Diagnostics* diags;
  HiSEPQMachine machine;
};

/// Rewrites `qvec.pair` into `llvm.call_intrinsic "llvm.riscv.qv.cx"`.
struct PairOpLowering : public OpRewritePattern<PairOp> {
  PairOpLowering(MLIRContext* ctx, Diagnostics* diags, HiSEPQMachine machine)
      : OpRewritePattern(ctx), diags(diags), machine(machine) {}

  LogicalResult matchAndRewrite(PairOp op, PatternRewriter& rewriter) const override {
    StringRef intrinsic = getPairGateIntrinsic(op.getGateKind());
    if (intrinsic.empty()) {
      return diags->report(op, "gate '" + stringifyPairGateKind(op.getGateKind()) + "' has no HiSEP-Q intrinsic");
    }

    auto lhs = resolveQubitVector(op, op.getLhsIn(), machine, *diags);
    if (!lhs) {
      return failure();
    }
    auto rhs = resolveQubitVector(op, op.getRhsIn(), machine, *diags);
    if (!rhs) {
      return failure();
    }

    SmallVector<Value> args{buildQubitVector(rewriter, op.getLoc(), *lhs),
                            buildQubitVector(rewriter, op.getLoc(), *rhs)};
    llvm::append_range(args, buildScalarOperands(rewriter, op.getLoc(), static_cast<unsigned>(lhs->indices.size()),
                                                 /*withTag=*/false));

    LLVM::CallIntrinsicOp::create(rewriter, op.getLoc(), rewriter.getStringAttr(intrinsic), args);

    // The instruction acts in place, so what comes out is what went in.
    rewriter.replaceOp(op, ValueRange{op.getLhsIn(), op.getRhsIn()});
    return success();
  }

  Diagnostics* diags;
  HiSEPQMachine machine;
};

/// Rewrites `qvec.measure z` into `llvm.riscv.qv.mz` and reads the outcomes back from `qv.mres`.
struct MeasureOpLowering : public OpRewritePattern<MeasureOp> {
  MeasureOpLowering(MLIRContext* ctx, Diagnostics* diags, HiSEPQMachine machine)
      : OpRewritePattern(ctx), diags(diags), machine(machine) {}

  LogicalResult matchAndRewrite(MeasureOp op, PatternRewriter& rewriter) const override {
    if (op.getBasis() != qcc::Basis::Z) {
      return diags->report(op, "basis '" + stringifyBasis(op.getBasis()) + "' has no HiSEP-Q intrinsic");
    }

    auto qubits = resolveQubitVector(op, op.getQubitsIn(), machine, *diags);
    if (!qubits) {
      return failure();
    }

    SmallVector<Value> outcomes = createMeasurement(rewriter, op.getLoc(), *qubits, machine);
    Value bits = vector::FromElementsOp::create(rewriter, op.getLoc(), op.getBits().getType(), outcomes);
    rewriter.replaceOp(op, ValueRange{op.getQubitsIn(), bits});
    return success();
  }

  Diagnostics* diags;
  HiSEPQMachine machine;
};

/// Rewrites `qvec.reset z` into a measurement followed by an `llvm.riscv.qv.x` on each qubit measured in |1⟩, since
/// HiSEP-Q has no reset instruction.
struct ResetOpLowering : public OpRewritePattern<ResetOp> {
  ResetOpLowering(MLIRContext* ctx, Diagnostics* diags, HiSEPQMachine machine)
      : OpRewritePattern(ctx), diags(diags), machine(machine) {}

  LogicalResult matchAndRewrite(ResetOp op, PatternRewriter& rewriter) const override {
    if (op.getBasis() != qcc::Basis::Z) {
      return diags->report(op, "basis '" + stringifyBasis(op.getBasis()) + "' has no HiSEP-Q lowering");
    }

    auto qubits = resolveQubitVector(op, op.getQubitsIn(), machine, *diags);
    if (!qubits) {
      return failure();
    }

    Location loc = op.getLoc();
    SmallVector<Value> outcomes = createMeasurement(rewriter, loc, *qubits, machine);

    // Flip each qubit that measured 1.
    const VectorType singleType = *machine.qubitVectorType(rewriter.getContext(), 1);
    for (auto [outcome, index] : llvm::zip_equal(outcomes, qubits->indices)) {
      scf::IfOp::create(rewriter, loc, outcome, [&](OpBuilder& builder, Location thenLoc) {
        createQubitsIntrinsic(builder, thenLoc, "llvm.riscv.qv.x",
                              ResolvedQubits{.indices = {index}, .qvType = singleType});
        scf::YieldOp::create(builder, thenLoc);
      });
    }

    // The instructions act in place, so what comes out is what went in.
    rewriter.replaceOp(op, ValueRange{op.getQubitsIn()});
    return success();
  }

  Diagnostics* diags;
  HiSEPQMachine machine;
};

/// Rewrites `qcf.if` into an `scf.if`.
///
/// The qubits which were bound by `qcf.if` now get captured in `scf.if`.
struct IfOpLowering : public OpRewritePattern<qcc::qcf::IfOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(qcc::qcf::IfOp op, PatternRewriter& rewriter) const override {
    ValueRange qubits = op.getQubitsIn();
    auto ifOp = scf::IfOp::create(rewriter, op.getLoc(), op.getClassicalResults().getTypes(), op.getCondition(),
                                  /*addThenBlock=*/false, /*addElseBlock=*/false);
    for (auto [from, to] : llvm::zip_equal(op->getRegions(), ifOp->getRegions())) {
      if (from.empty()) {
        continue; // An omitted else region, which implies no classical results.
      }
      Block* block = rewriter.createBlock(&to);
      rewriter.mergeBlocks(&from.front(), block, qubits);
      Operation* yield = block->getTerminator();
      rewriter.setInsertionPoint(yield);
      rewriter.replaceOpWithNewOp<scf::YieldOp>(yield, yield->getOperands().drop_front(qubits.size()));
    }

    SmallVector<Value> replacements = llvm::to_vector(qubits);
    llvm::append_range(replacements, ifOp.getResults());
    rewriter.replaceOp(op, replacements);
    return success();
  }
};

/// Erases an `aux` output recording op.
///
/// TODO: Lower them properly once HiSEP-Q specifies how a program reports its results.
template <typename RecordOp> struct RecordOpErasure : public OpRewritePattern<RecordOp> {
  using OpRewritePattern<RecordOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(RecordOp op, PatternRewriter& rewriter) const override {
    rewriter.eraseOp(op);
    return success();
  }
};

} // namespace

namespace qcc {

#define GEN_PASS_DEF_CONVERTQVECTOHISEPQINTRINSICS
#include "qcc/Conversion/ToHiSEPQ/ToHiSEPQ.h.inc"

namespace {

struct ConvertQVecToHiSEPQIntrinsics final : impl::ConvertQVecToHiSEPQIntrinsicsBase<ConvertQVecToHiSEPQIntrinsics> {
  using ConvertQVecToHiSEPQIntrinsicsBase::ConvertQVecToHiSEPQIntrinsicsBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();

    if (!HiSEPQMachine::isSupportedMinVLen(minVLen)) {
      emitError(moduleOp.getLoc()) << "'min-vlen' expects a power of two of at least 64, got " << Twine(minVLen);
      return signalPassFailure();
    }

    if (!HiSEPQMachine::isSupportedNumQubitControlLines(numQubitControlLines)) {
      emitError(moduleOp.getLoc()) << "'num-qubit-control-lines' expects 1 to "
                                   << Twine(HiSEPQMachine::maxNumQubitControlLines()) << ", got "
                                   << Twine(numQubitControlLines);
      return signalPassFailure();
    }

    const HiSEPQMachine machine(minVLen, numQubitControlLines);

    Diagnostics diags;
    RewritePatternSet loweringPatterns(ctx);
    loweringPatterns.add<SingleOpLowering, PairOpLowering, MeasureOpLowering, ResetOpLowering>(ctx, &diags, machine);
    loweringPatterns.add<IfOpLowering>(ctx);
    walkAndApplyPatterns(moduleOp, std::move(loweringPatterns));
    if (diags.hadError) {
      return signalPassFailure();
    }

    // We make the record op erasure (workaround) separately in a *greedy* driver which also eliminates dead code now.
    // This can be done now because intrinsics (in contrast to qvec ops) have memory effects.
    RewritePatternSet cleanupPatterns(ctx);
    cleanupPatterns.add<RecordOpErasure<aux::RecordIntOp>, RecordOpErasure<aux::RecordMemRefOp>>(ctx);
    if (failed(applyPatternsGreedily(moduleOp, std::move(cleanupPatterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
