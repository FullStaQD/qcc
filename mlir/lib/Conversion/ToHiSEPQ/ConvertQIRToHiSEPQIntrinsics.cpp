// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/ToQIR/Constants.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Value.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LogicalResult.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <limits>
#include <optional>
#include <utility>

using namespace mlir;

namespace {

enum class QVClass : std::uint8_t {
  Single = 1, // (vs1: vec<[8]xi8>, rs2: i32, block_imm: i32, vl: i32)
  Pair = 2,   // (vs1: vec<[8]xi8>, vs2: vec<[8]xi8>, block_imm: i32, vl: i32)
};

/// A QIR QIS function's RISC-V QV intrinsic counterpart.
struct QISOpInfo {
  StringRef intrinsicName;
  QVClass qvClass;

  [[nodiscard]] unsigned getNumQubitOperands() const { return static_cast<unsigned>(qvClass); }
};

} // namespace

/// Maps a QIR QIS function name to its RISC-V QV intrinsic info.
/// Returns std::nullopt for unrecognized / unsupported names.

static std::optional<QISOpInfo> getQISOpInfo(StringRef qisName) {
  static const llvm::StringMap<QISOpInfo> table = {
      {qcc::qirQisH, {.intrinsicName = "llvm.riscv.qv.h", .qvClass = QVClass::Single}},
      {qcc::qirQisX, {.intrinsicName = "llvm.riscv.qv.x", .qvClass = QVClass::Single}},
      {qcc::qirQisCX, {.intrinsicName = "llvm.riscv.qv.cx", .qvClass = QVClass::Pair}},
      {qcc::qirQisMZ, {.intrinsicName = "llvm.riscv.qv.mz", .qvClass = QVClass::Single}},
  };
  auto it = table.find(qisName);
  return it == table.end() ? std::nullopt : std::optional(it->second);
}

/// Returns true when `name` is a QIR runtime / QIS symbol.
static bool isQIRSymbol(StringRef name) { return name.starts_with("__quantum__"); }

/// Tries to extract the qubit index encoded in a ptr obtained via:
///   `llvm.inttoptr (llvm.mlir.constant N : i64) : !llvm.ptr`
static std::optional<int64_t> getQubitIndexFromPtr(Value ptrValue) {
  auto intToPtrOp = ptrValue.getDefiningOp<LLVM::IntToPtrOp>();
  if (!intToPtrOp) {
    return std::nullopt;
  }

  auto constOp = intToPtrOp.getArg().getDefiningOp<LLVM::ConstantOp>();
  if (!constOp) {
    return std::nullopt;
  }

  auto intAttr = dyn_cast<IntegerAttr>(constOp.getValue());
  if (!intAttr) {
    return std::nullopt;
  }

  return intAttr.getInt();
}

/// Encodes a qubit index as a `vector<[8]xi8>` scalable vector for QV intrinsics.
/// The index is inserted into lane 0 of a poison vector. The `nxv8i8` element
/// type matches the HiSEP-Q RISC-V backend's QV instruction-selection patterns.
///
/// The poison base is deliberate. We emit every QV intrinsic with `vl = 1`, so
/// only lane 0 is ever read and the lanes above it are genuinely don't-care.
///
/// `index` must fit in an unsigned i8 (callers are expected to have validated
/// this already and to report a compiler error otherwise).
static Value qubitIndexToVec(OpBuilder& builder, Location loc, int64_t index) {
  assert(index >= 0 && std::cmp_less_equal(index, std::numeric_limits<uint8_t>::max()) &&
         "qubit index does not fit in i8");

  auto i8Type = builder.getIntegerType(8);
  auto i32Type = builder.getI32Type();
  auto vecType = VectorType::get({8}, i8Type, /*scalableDims=*/{true});

  Value indexConst = LLVM::ConstantOp::create(builder, loc, i8Type, builder.getIntegerAttr(i8Type, index));
  Value poisonVec = LLVM::PoisonOp::create(builder, loc, vecType);
  Value lane = LLVM::ConstantOp::create(builder, loc, i32Type, builder.getI32IntegerAttr(0));
  Value insertElmOp = LLVM::InsertElementOp::create(builder, loc, poisonVec, indexConst, lane);
  return insertElmOp;
}

namespace {

/// Rewrites `llvm.call @__quantum__qis__*__body(qubit_ptr, ...)` into the
/// corresponding `llvm.call_intrinsic "llvm.riscv.qv.*"(vec, ...)`.
///
/// Qubit pointer arguments (produced by `llvm.inttoptr` of a constant index)
/// are re-encoded as `vector<[8]xi8>` scalable vectors.
struct QISCallLowering : public OpRewritePattern<LLVM::CallOp> {
  QISCallLowering(MLIRContext* ctx, bool* hadError) : OpRewritePattern(ctx), hadError(hadError) {
    assert(hadError != nullptr && "hadError must point to storage owned by the pass");
  }

  LogicalResult matchAndRewrite(LLVM::CallOp callOp, PatternRewriter& rewriter) const override {
    auto callee = callOp.getCallee();
    if (!callee) {
      return failure();
    }

    std::optional<QISOpInfo> info = getQISOpInfo(*callee);
    if (!info) {
      return failure();
    }

    auto operands = callOp.getArgOperands();
    unsigned numQubitOperands = info->getNumQubitOperands();

    if (operands.size() < numQubitOperands) {
      callOp.emitError("'") << *callee << "' expects at least " << numQubitOperands << " qubit operand(s), got "
                            << operands.size();
      *hadError = true;
      return failure();
    }

    SmallVector<int64_t> qubitIndices;
    for (unsigned i = 0; i < numQubitOperands; ++i) {
      auto idx = getQubitIndexFromPtr(operands[i]);
      if (!idx) {
        callOp.emitError("cannot extract qubit index from ptr for '") << *callee << "'";
        *hadError = true;
        return failure();
      }
      if (*idx < 0 || std::cmp_greater(*idx, std::numeric_limits<uint8_t>::max())) {
        callOp.emitError("qubit index ") << *idx << " out of range for '" << *callee << "'";
        *hadError = true;
        return failure();
      }
      qubitIndices.push_back(*idx);
    }

    auto loc = callOp.getLoc();
    auto i32Type = rewriter.getI32Type();

    Value blockImm = LLVM::ConstantOp::create(rewriter, loc, i32Type, rewriter.getI32IntegerAttr(0));
    Value vl = LLVM::ConstantOp::create(rewriter, loc, i32Type, rewriter.getI32IntegerAttr(1));

    SmallVector<Value> args;
    switch (info->qvClass) {
    case QVClass::Single: {
      // (vs1: vec<[8]xi8>, rs2: i32, block_imm: i32, vl: i32)
      // For mz__body: operands[0] = qubit_ptr, operands[1] = result_ptr (unused here; see ReadResultLowering).
      Value tag = LLVM::ConstantOp::create(rewriter, loc, i32Type, rewriter.getI32IntegerAttr(0));
      args.push_back(qubitIndexToVec(rewriter, loc, qubitIndices[0]));
      args.push_back(tag);
      args.push_back(blockImm);
      args.push_back(vl);
      break;
    }
    case QVClass::Pair:
      // (vs1: vec<[8]xi8>, vs2: vec<[8]xi8>, block_imm: i32, vl: i32)
      args.push_back(qubitIndexToVec(rewriter, loc, qubitIndices[0]));
      args.push_back(qubitIndexToVec(rewriter, loc, qubitIndices[1]));
      args.push_back(blockImm);
      args.push_back(vl);
      break;
    }

    LLVM::CallIntrinsicOp::create(rewriter, loc, rewriter.getStringAttr(info->intrinsicName), args);
    rewriter.eraseOp(callOp);
    return success();
  }

  bool* hadError;
};

/// Replaces `llvm.call @__quantum__rt__read_result(%result_ptr)` with `poison : i1`.
///
/// TODO: A proper `qv.read_result` intrinsic is not yet defined in IntrinsicsRISCVXQV.td.
struct ReadResultLowering : public OpRewritePattern<LLVM::CallOp> {
  using OpRewritePattern<LLVM::CallOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(LLVM::CallOp callOp, PatternRewriter& rewriter) const override {
    auto callee = callOp.getCallee();
    if (!callee || *callee != qcc::qirRtReadResult) {
      return failure();
    }

    rewriter.replaceOpWithNewOp<LLVM::PoisonOp>(callOp, rewriter.getI1Type());
    return success();
  }
};

/// Erases `llvm.call @__quantum__rt__initialize(ptr)`.
/// TODO: A proper QISA specification by HiSEP-Q for initialization is needed.
struct RtInitLowering : public OpRewritePattern<LLVM::CallOp> {
  using OpRewritePattern<LLVM::CallOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(LLVM::CallOp callOp, PatternRewriter& rewriter) const override {
    auto callee = callOp.getCallee();
    if (!callee || *callee != qcc::qirRtInit) {
      return failure();
    }

    rewriter.eraseOp(callOp);
    return success();
  }
};

/// Erases the QIR output-recording runtime calls
/// (`__quantum__rt__{bool,int,array,tuple}_record_output`).
///
/// TODO: No intrinsic equivalent for output recording exists yet.
struct RecordOutputLowering : public OpRewritePattern<LLVM::CallOp> {
  using OpRewritePattern<LLVM::CallOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(LLVM::CallOp callOp, PatternRewriter& rewriter) const override {
    auto callee = callOp.getCallee();
    if (!callee) {
      return failure();
    }

    if (*callee != qcc::qirRtBoolRecordOutput && *callee != qcc::qirRtIntRecordOutput &&
        *callee != qcc::qirRtArrayRecordOutput && *callee != qcc::qirRtTupleRecordOutput) {
      return failure();
    }

    rewriter.eraseOp(callOp);
    return success();
  }
};

} // namespace

namespace qcc {

#define GEN_PASS_DEF_CONVERTQIRTOHISEPQINTRINSICS
#include "qcc/Conversion/ToHiSEPQ/ToHiSEPQ.h.inc"

namespace {

struct ConvertQIRToHiSEPQIntrinsics final : impl::ConvertQIRToHiSEPQIntrinsicsBase<ConvertQIRToHiSEPQIntrinsics> {
  using ConvertQIRToHiSEPQIntrinsicsBase::ConvertQIRToHiSEPQIntrinsicsBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();

    bool hadError = false;
    RewritePatternSet patterns(ctx);
    patterns.add<QISCallLowering>(ctx, &hadError);
    patterns.add<ReadResultLowering, RtInitLowering, RecordOutputLowering>(ctx);

    if (failed(applyPatternsGreedily(moduleOp, std::move(patterns))) || hadError) {
      return signalPassFailure();
    }

    removeUnusedQIRSymbols();
  }

private:
  /// Removes QIR function declarations and globals that have no remaining uses.
  ///
  /// Besides the `__quantum__*` declarations this also drops the dummy output
  /// label.
  void removeUnusedQIRSymbols() {
    ModuleOp moduleOp = getOperation();
    SmallVector<Operation*> toErase;

    moduleOp.walk([&](LLVM::LLVMFuncOp funcOp) {
      if (isQIRSymbol(funcOp.getName()) && SymbolTable::symbolKnownUseEmpty(funcOp, moduleOp)) {
        toErase.push_back(funcOp);
      }
    });

    moduleOp.walk([&](LLVM::GlobalOp globalOp) {
      if (globalOp.getSymName() == qcc::qirDummyLabelGlobalSymbolName &&
          SymbolTable::symbolKnownUseEmpty(globalOp, moduleOp)) {
        toErase.push_back(globalOp);
      }
    });

    for (auto* op : toErase) {
      op->erase();
    }
  }
};

} // namespace
} // namespace qcc
