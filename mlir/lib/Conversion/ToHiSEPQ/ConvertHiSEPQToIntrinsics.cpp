// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/HiSEPQ/IR/HiSEPQ.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/QC/IR/QCDialect.h" // FIXME: check clangd unused include warning
#include "mlir/Dialect/QC/IR/QCOps.h"
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

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <limits>
#include <optional>
#include <utility>

using namespace mlir;
using namespace qcc::hisepq;

namespace {

// FIXME: max qubit count (~ LMUL_MAX) and qubits per register (~ VLEN) should be datalayout parameter.

/// The qubit (element) count of a QV vector register at LMUL 1.
constexpr unsigned qvQubitsPerRegister = 8; // FIXME: should be 16 at VLEN=128 and SEW=8?

/// The largest qubit (element) count the QV instructions can address, i.e. LMUL 8.
constexpr unsigned qvMaxQubits = 64; // LMUL_MAX * qubits_per_register

/// Returns the scalable vector type that carries `numQubits` qubit indices.
///
/// The backend selects the QV instructions only for `nxv8i8`, `nxv16i8`, `nxv32i8` and `nxv64i8` (LMUL 1, 2, 4 and 8).
/// We pick the narrowest one that fits.
///
/// Returns nullopt when there are more qubits than even LMUL 8 can hold.
std::optional<VectorType> getQubitVectorType(MLIRContext* ctx, unsigned numQubits) {
  if (numQubits > qvMaxQubits) {
    return std::nullopt;
  }

  unsigned minElements = qvQubitsPerRegister;
  while (minElements < numQubits) {
    minElements *= 2;
  }

  return VectorType::get({minElements}, IntegerType::get(ctx, 8), /*scalableDims=*/{true});
}

/// Reads the qubit indices out of a vector by tracing to `qc.static`.
///
/// Only a `vector.from_elements` of `qc.static` ops is understood.
std::optional<SmallVector<int64_t>> getQubitIndices(Value qubitVector) {
  auto fromElementsOp = qubitVector.getDefiningOp<vector::FromElementsOp>();
  if (!fromElementsOp) {
    return std::nullopt;
  }

  SmallVector<int64_t> indices;
  for (Value element : fromElementsOp.getElements()) {
    auto staticOp = element.getDefiningOp<qc::StaticOp>();
    if (!staticOp) {
      return std::nullopt;
    }
    indices.push_back(static_cast<int64_t>(staticOp.getIndex()));
  }

  return indices;
}

/// Materializes qubit indices for use as operand of a qv intrinsic.
///
/// The indices become one dense `vector<Nxi8>` constant, which is then inserted into a poison
/// scalable vector of `qvType`. The poison base is deliberate: the intrinsic is emitted with
/// `vl = N`, so the lanes above the last index are never read.
Value buildQubitVector(OpBuilder& builder, Location loc, ArrayRef<int64_t> qubitIndices, VectorType qvType) {
  auto i8Type = builder.getIntegerType(8);
  auto fixedType = VectorType::get({static_cast<int64_t>(qubitIndices.size())}, i8Type);

  SmallVector<APInt> indexValues;
  indexValues.reserve(qubitIndices.size());
  for (int64_t index : qubitIndices) {
    assert(0 <= index && index < 256 && "does not fit into 8 bits");
    indexValues.emplace_back(/*numBits=*/8, static_cast<uint64_t>(index));
  }

  Value qubitVec = LLVM::ConstantOp::create(builder, loc, fixedType, DenseElementsAttr::get(fixedType, indexValues));
  Value poisonVec = LLVM::PoisonOp::create(builder, loc, qvType);

  return LLVM::vector_insert::create(builder, loc, poisonVec, qubitVec, /*pos=*/0);
}

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

/// Lowers the qubit operands of `op` for consumption by the corresponding intrinsic.
std::optional<Value> lowerQubitVector(Operation* op, TypedValue<VectorType> qubits, OpBuilder& builder,
                                      Diagnostics& diags) {
  auto indices = getQubitIndices(qubits);
  if (!indices) {
    (void)diags.report(op, "expects every qubit vector to be a 'vector.from_elements' of 'qc.static' operations");
    return std::nullopt;
  }

  for (int64_t index : *indices) {
    if (std::cmp_greater(index, std::numeric_limits<uint8_t>::max())) {
      (void)diags.report(op, "qubit index " + Twine(index) + " does not fit in i8");
      return std::nullopt;
    }
  }

  auto qvType = getQubitVectorType(op->getContext(), indices->size());
  if (!qvType) {
    (void)diags.report(op, "has " + Twine(indices->size()) + " qubits, but the QV instructions address at most " +
                               Twine(qvMaxQubits));
    return std::nullopt;
  }

  return buildQubitVector(builder, op->getLoc(), *indices, *qvType);
}

/// Returns the intrinsic implementing `gate`, or an empty ref if there is none.
StringRef getSingleGateIntrinsic(SingleGate gate) {
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
StringRef getPairGateIntrinsic(PairGate gate) {
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
SmallVector<Value> buildScalarOperands(OpBuilder& builder, Location loc, unsigned numQubits, bool withTag) {
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

/// Rewrites `hisepq.single` into `llvm.call_intrinsic "llvm.riscv.qv.{h,x,...}"`.
struct SingleOpLowering : public OpRewritePattern<SingleOp> {
  SingleOpLowering(MLIRContext* ctx, Diagnostics* diags) : OpRewritePattern(ctx), diags(diags) {}

  LogicalResult matchAndRewrite(SingleOp op, PatternRewriter& rewriter) const override {
    StringRef intrinsic = getSingleGateIntrinsic(op.getGate());
    if (intrinsic.empty()) {
      return diags->report(op, "gate '" + stringifySingleGate(op.getGate()) + "' has no HiSEP-Q intrinsic");
    }

    auto qubits = lowerQubitVector(op, op.getQubits(), rewriter, *diags);
    if (!qubits) {
      return failure();
    }

    auto numQubits = cast<VectorType>(op.getQubits().getType()).getNumElements();
    SmallVector<Value> args{*qubits};
    llvm::append_range(args, buildScalarOperands(rewriter, op.getLoc(), numQubits, /*withTag=*/true));

    LLVM::CallIntrinsicOp::create(rewriter, op.getLoc(), rewriter.getStringAttr(intrinsic), args);
    rewriter.eraseOp(op);
    return success();
  }

  Diagnostics* diags;
};

/// Rewrites `hisepq.pair` into `llvm.call_intrinsic "llvm.riscv.qv.cx"`.
struct PairOpLowering : public OpRewritePattern<PairOp> {
  PairOpLowering(MLIRContext* ctx, Diagnostics* diags) : OpRewritePattern(ctx), diags(diags) {}

  LogicalResult matchAndRewrite(PairOp op, PatternRewriter& rewriter) const override {
    StringRef intrinsic = getPairGateIntrinsic(op.getGate());
    if (intrinsic.empty()) {
      return diags->report(op, "gate '" + stringifyPairGate(op.getGate()) + "' has no HiSEP-Q intrinsic");
    }

    auto ctrls = lowerQubitVector(op, op.getCtrls(), rewriter, *diags);
    if (!ctrls) {
      return failure();
    }
    // FIXME: IR might already be mutated here! Failure in next if would be wrong then.
    auto tgts = lowerQubitVector(op, op.getTgts(), rewriter, *diags);
    if (!tgts) {
      return failure();
    }

    auto numCtrls = cast<VectorType>(op.getCtrls().getType()).getNumElements();
    // FIXME: Why swapping tgts and ctrls?
    SmallVector<Value> args{*tgts, *ctrls};
    llvm::append_range(args, buildScalarOperands(rewriter, op.getLoc(), numCtrls, /*withTag=*/false));

    LLVM::CallIntrinsicOp::create(rewriter, op.getLoc(), rewriter.getStringAttr(intrinsic), args);
    rewriter.eraseOp(op);
    return success();
  }

  Diagnostics* diags;
};

/// Rewrites `hisepq.mz` into `llvm.call_intrinsic "llvm.riscv.qv.mz"` plus a poison result.
///
/// TODO: The QISA specifies no way to read a measurement back, so the classical bits are lost
/// here. Replace the poison with a real read once `IntrinsicsRISCVXQV.td` gains an intrinsic for
/// it. Until then a program that branches on a measurement silently gets garbage.
struct MzOpLowering : public OpRewritePattern<MzOp> {
  MzOpLowering(MLIRContext* ctx, Diagnostics* diags) : OpRewritePattern(ctx), diags(diags) {}

  LogicalResult matchAndRewrite(MzOp op, PatternRewriter& rewriter) const override {
    auto qubits = lowerQubitVector(op, op.getQubits(), rewriter, *diags);
    if (!qubits) {
      return failure();
    }

    auto numLanes = cast<VectorType>(op.getQubits().getType()).getNumElements();
    SmallVector<Value> args{*qubits};
    llvm::append_range(args, buildScalarOperands(rewriter, op.getLoc(), numLanes, /*withTag=*/true));

    LLVM::CallIntrinsicOp::create(rewriter, op.getLoc(), rewriter.getStringAttr("llvm.riscv.qv.mz"), args);
    rewriter.replaceOpWithNewOp<LLVM::PoisonOp>(op, op.getResult().getType()); // Workaround
    return success();
  }

  Diagnostics* diags;
};

} // namespace

namespace qcc {

#define GEN_PASS_DEF_CONVERTHISEPQTOINTRINSICS
#include "qcc/Conversion/ToHiSEPQ/ToHiSEPQ.h.inc"

namespace {

struct ConvertHiSEPQToIntrinsics final : impl::ConvertHiSEPQToIntrinsicsBase<ConvertHiSEPQToIntrinsics> {
  using ConvertHiSEPQToIntrinsicsBase::ConvertHiSEPQToIntrinsicsBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();

    Diagnostics diags;
    RewritePatternSet patterns(ctx);
    patterns.add<SingleOpLowering, PairOpLowering, MzOpLowering>(ctx, &diags);

    if (failed(applyPatternsGreedily(moduleOp, std::move(patterns))) || diags.hadError) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
