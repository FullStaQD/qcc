// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVec.h"
#include "qcc/Dialect/QVec/QVecMachine.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/QCO/IR/QCODialect.h" // FIXME: check clangd unused include warning
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

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <limits>
#include <optional>
#include <utility>

using namespace mlir;
using namespace qcc::qvec;

namespace {

/// A qubit vector operand reduced to what the intrinsic needs from it.
struct ResolvedQubits {
  /// One static qubit index per vector element.
  SmallVector<int64_t> indices;
  /// The scalable `<vscale x N x i8>` type the indices have to be handed over in.
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
/// The indices become one dense `vector<Nxi8>` constant, which is then inserted into a poison
/// scalable vector of `qvType`. The poison base is deliberate: the intrinsic is emitted with
/// `vl = N`, so the elements above the last index are never read.
static Value buildQubitVector(OpBuilder& builder, Location loc, const ResolvedQubits& qubits) {
  ArrayRef<int64_t> qubitIndices = qubits.indices;
  VectorType qvType = qubits.qvType;

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

/// Checks a qubit operand of `op` and works out what the intrinsic needs for it.
///
/// Emits nothing, so that an operation with two qubit operands can have both of them validated
/// before any of them is materialized.
static std::optional<ResolvedQubits> resolveQubitVector(Operation* op, TypedValue<VectorType> qubits,
                                                        const Machine& machine, Diagnostics& diags) {
  auto indices = getQubitIndices(qubits);
  if (!indices) {
    (void)diags.report(op, "expects every qubit vector element to trace back to a 'qco.static' operation");
    return std::nullopt;
  }

  for (int64_t index : *indices) {
    if (std::cmp_greater(index, std::numeric_limits<uint8_t>::max())) {
      (void)diags.report(op, "qubit index " + Twine(index) + " does not fit in i8");
      return std::nullopt;
    }
  }

  auto numQubits = indices->size();
  auto qvType = machine.qubitVectorType(op->getContext(), static_cast<unsigned>(numQubits));
  if (!qvType) {
    (void)diags.report(op, "has " + Twine(indices->size()) + " qubits, but at a minimum VLEN of " +
                               Twine(machine.minVLen) + " the QV instructions address at most " +
                               Twine(machine.maxQubits()));
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
  SingleOpLowering(MLIRContext* ctx, Diagnostics* diags, Machine machine)
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
  Machine machine;
};

/// Rewrites `qvec.pair` into `llvm.call_intrinsic "llvm.riscv.qv.cx"`.
struct PairOpLowering : public OpRewritePattern<PairOp> {
  PairOpLowering(MLIRContext* ctx, Diagnostics* diags, Machine machine)
      : OpRewritePattern(ctx), diags(diags), machine(machine) {}

  LogicalResult matchAndRewrite(PairOp op, PatternRewriter& rewriter) const override {
    StringRef intrinsic = getPairGateIntrinsic(op.getGateKind());
    if (intrinsic.empty()) {
      return diags->report(op, "gate '" + stringifyPairGate(op.getGateKind()) + "' has no HiSEP-Q intrinsic");
    }

    auto ctrls = resolveQubitVector(op, op.getLhsIn(), machine, *diags);
    if (!ctrls) {
      return failure();
    }
    auto tgts = resolveQubitVector(op, op.getRhsIn(), machine, *diags);
    if (!tgts) {
      return failure();
    }

    // FIXME: Why swapping tgts and ctrls?
    SmallVector<Value> args{buildQubitVector(rewriter, op.getLoc(), *tgts),
                            buildQubitVector(rewriter, op.getLoc(), *ctrls)};
    llvm::append_range(args, buildScalarOperands(rewriter, op.getLoc(), static_cast<unsigned>(ctrls->indices.size()),
                                                 /*withTag=*/false));

    LLVM::CallIntrinsicOp::create(rewriter, op.getLoc(), rewriter.getStringAttr(intrinsic), args);

    // The instruction acts in place, so what comes out is what went in.
    rewriter.replaceOp(op, ValueRange{op.getLhsIn(), op.getRhsIn()});
    return success();
  }

  Diagnostics* diags;
  Machine machine;
};

/// Rewrites `qvec.mz` into `llvm.call_intrinsic "llvm.riscv.qv.mz"` plus a poison result.
///
/// TODO: The QISA specifies no way to read a measurement back, so the classical bits are lost
/// here. Replace the poison with a real read once `IntrinsicsRISCVXQV.td` gains an intrinsic for
/// it. Until then a program that branches on a measurement silently gets garbage.
struct MzOpLowering : public OpRewritePattern<MzOp> {
  MzOpLowering(MLIRContext* ctx, Diagnostics* diags, Machine machine)
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
  Machine machine;
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

    const Machine machine = Machine::fromModule(moduleOp);

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
