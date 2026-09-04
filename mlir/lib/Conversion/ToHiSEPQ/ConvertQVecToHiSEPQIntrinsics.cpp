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
#include "qcc/Dialect/QVec/IR/QVec.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/QCO/IR/QCOOps.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
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

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/MathExtras.h"

#include <cstdint>
#include <optional>
#include <utility>

using namespace mlir;
using namespace qcc::qvec;
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

/// Reads the qubit indices out of a vector by tracing every element to a `qco.static`.
static std::optional<SmallVector<int64_t>> getQubitIndices(TypedValue<VectorType> qubitVector) {
  SmallVector<int64_t> indices;
  for (int64_t index = 0; index < qubitVector.getType().getNumElements(); ++index) {
    qco::StaticOp staticOp = getStaticOpAncestor(qubitVector, index);
    if (!staticOp) {
      return std::nullopt;
    }
    indices.push_back(static_cast<int64_t>(staticOp.getIndex()));
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
    (void)diags.report(op, "expects every qubit vector element to trace back to a 'qco.static' operation");
    return std::nullopt;
  }

  const unsigned qew = machine.getQubitElementWidth();
  for (int64_t index : *indices) {
    if (std::cmp_greater(index, machine.maxQubitIndex())) {
      (void)diags.report(op, "qubit index " + Twine(index) + " does not fit in i" + Twine(qew));
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
static StringRef getSingleGateIntrinsic(SingleGate gate) {
  switch (gate) {
  case SingleGate::H:
    return "llvm.riscv.qv.h";
  case SingleGate::X:
    return "llvm.riscv.qv.x";
  case SingleGate::I:
  case SingleGate::Y:
  case SingleGate::Z:
  case SingleGate::S:
  case SingleGate::Sdg:
  case SingleGate::T:
  case SingleGate::Tdg:
    return {};
  }
  return {};
}

/// Returns the intrinsic implementing `gate`, or an empty ref if there is none.
static StringRef getPairGateIntrinsic(PairGate gate) {
  switch (gate) {
  case PairGate::CX:
    return "llvm.riscv.qv.cx";
  case PairGate::CY:
  case PairGate::CZ:
  case PairGate::iSWAP:
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

namespace {

/// Rewrites `qvec.single` into `llvm.call_intrinsic "llvm.riscv.qv.{h,x,...}"`.
struct SingleOpLowering : public OpRewritePattern<SingleOp> {
  SingleOpLowering(MLIRContext* ctx, Diagnostics* diags, HiSEPQMachine machine)
      : OpRewritePattern(ctx), diags(diags), machine(machine) {}

  LogicalResult matchAndRewrite(SingleOp op, PatternRewriter& rewriter) const override {
    StringRef intrinsic = getSingleGateIntrinsic(op.getGateKind());
    if (intrinsic.empty()) {
      return diags->report(op, "gate '" + stringifySingleGate(op.getGateKind()) + "' has no HiSEP-Q intrinsic");
    }

    auto qubits = resolveQubitVector(op, op.getQubitsIn(), machine, *diags);
    if (!qubits) {
      return failure();
    }

    SmallVector<Value> args{buildQubitVector(rewriter, op.getLoc(), *qubits)};
    llvm::append_range(args, buildScalarOperands(rewriter, op.getLoc(), static_cast<unsigned>(qubits->indices.size()),
                                                 /*withTag=*/true));

    LLVM::CallIntrinsicOp::create(rewriter, op.getLoc(), rewriter.getStringAttr(intrinsic), args);

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
      return diags->report(op, "gate '" + stringifyPairGate(op.getGateKind()) + "' has no HiSEP-Q intrinsic");
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

/// Rewrites `qvec.mz` into `llvm.call_intrinsic "llvm.riscv.qv.mz"` plus a poison result.
///
/// TODO: The QISA specifies no way to read a measurement back, so the classical bits are lost
/// here. Replace the poison with a real read once `IntrinsicsRISCVXQV.td` gains an intrinsic for
/// it. Until then a program that branches on a measurement silently gets garbage.
struct MzOpLowering : public OpRewritePattern<MzOp> {
  MzOpLowering(MLIRContext* ctx, Diagnostics* diags, HiSEPQMachine machine)
      : OpRewritePattern(ctx), diags(diags), machine(machine) {}

  LogicalResult matchAndRewrite(MzOp op, PatternRewriter& rewriter) const override {
    auto qubits = resolveQubitVector(op, op.getQubitsIn(), machine, *diags);
    if (!qubits) {
      return failure();
    }

    SmallVector<Value> args{buildQubitVector(rewriter, op.getLoc(), *qubits)};
    llvm::append_range(args, buildScalarOperands(rewriter, op.getLoc(), static_cast<unsigned>(qubits->indices.size()),
                                                 /*withTag=*/true));

    LLVM::CallIntrinsicOp::create(rewriter, op.getLoc(), rewriter.getStringAttr("llvm.riscv.qv.mz"), args);

    Value bits = LLVM::PoisonOp::create(rewriter, op.getLoc(), op.getBits().getType()); // Workaround
    rewriter.replaceOp(op, ValueRange{op.getQubitsIn(), bits});
    return success();
  }

  Diagnostics* diags;
  HiSEPQMachine machine;
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

    // A VLEN below `64` would make `vscale` a fraction, and anything that is not a power of two is not a VLEN at all.
    if (minVLen < 64 || !llvm::isPowerOf2_32(minVLen)) {
      emitError(moduleOp.getLoc()) << "'min-vlen' expects a power of two of at least 64, got " << Twine(minVLen);
      return signalPassFailure();
    }

    // 8 and 16 are the only save values for QEW for our currently hardcoded set of possible LMUL values (see
    // HiSEPQMachine).
    if (qubitElementWidth != 8 && qubitElementWidth != 16) {
      emitError(moduleOp.getLoc()) << "'qubit-element-width' expects 8 or 16, got " << Twine(qubitElementWidth);
      return signalPassFailure();
    }

    const HiSEPQMachine machine(minVLen, qubitElementWidth);

    Diagnostics diags;
    RewritePatternSet patterns(ctx);
    patterns.add<SingleOpLowering, PairOpLowering, MzOpLowering>(ctx, &diags, machine);

    if (failed(applyPatternsGreedily(moduleOp, std::move(patterns))) || diags.hadError) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
