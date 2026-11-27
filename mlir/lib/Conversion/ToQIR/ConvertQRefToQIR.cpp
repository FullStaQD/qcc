// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Constants.h"
#include "qcc/Conversion/ToQIR/Constants.h"
#include "qcc/Conversion/ToQIR/ToQIR.h" // IWYU pragma: keep
#include "qcc/Dialect/Aux_/IR/Aux_.h"
#include "qcc/Dialect/QRef/IR/QRef.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/LLVMIR/LLVMTypes.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/TypeRange.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Support/LLVM.h"
#include "mlir/Support/LogicalResult.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/TypeSwitch.h"

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <string>
#include <tuple>

using namespace mlir;
using namespace qcc;

/// Returns the QIR QIS function of a single-qubit gate of `kind`, or an empty string if the gate is not among the
/// supported native gate set.
///
/// TODO: The native gate set is currently hardcoded.
static StringRef getQISFunction(SingleGateKind kind) {
  switch (kind) {
  case SingleGateKind::X:
    return qcc::qirQisX;
  case SingleGateKind::H:
    return qcc::qirQisH;
  case SingleGateKind::RZ:
    return qcc::qirQisRZ;
  case SingleGateKind::S:
    return qcc::qirQisS;
  case SingleGateKind::Sdg:
    return qcc::qirQisSdg;
  case SingleGateKind::T:
    return qcc::qirQisT;
  case SingleGateKind::Tdg:
    return qcc::qirQisTdg;
  default:
    return "";
  }
}

/// Returns the QIR QIS function of a two-qubit gate of `kind`, or an empty string if the gate is not among the
/// supported native gate set.
///
/// TODO: The native gate set is currently hardcoded.
static StringRef getQISFunction(PairGateKind kind) { return kind == PairGateKind::CX ? qcc::qirQisCX : ""; }

/// Whether an operand or a result of `op` holds qubit references.
static bool holdsQubitRefs(Operation* op) {
  return llvm::any_of(op->getOperandTypes(), isQubitRefOrArray) ||
         llvm::any_of(op->getResultTypes(), isQubitRefOrArray);
}

/// Checks that the qref op `op` has a counterpart among the QIR QIS functions.
static LogicalResult checkSupported(Operation* op, StringRef passName) {
  return llvm::TypeSwitch<Operation*, LogicalResult>(op)
      .Case([&](qref::SingleOp single) -> LogicalResult {
        if (getQISFunction(single.getGateKind()).empty()) {
          return single.emitOpError() << "applies gate '" << stringifySingleGateKind(single.getGateKind())
                                      << "', which " << passName << " does not support";
        }
        return success();
      })
      .Case([&](qref::PairOp pair) -> LogicalResult {
        if (getQISFunction(pair.getGateKind()).empty()) {
          return pair.emitOpError() << "applies gate '" << stringifyPairGateKind(pair.getGateKind()) << "', which "
                                    << passName << " does not support";
        }
        return success();
      })
      .Case([&](qref::MeasureOp measure) -> LogicalResult {
        if (measure.getBasis() != Basis::Z) {
          return measure.emitOpError() << "measures in basis '" << stringifyBasis(measure.getBasis()) << "', which "
                                       << passName << " does not support";
        }
        return success();
      })
      .Case([&](qref::ResetOp reset) -> LogicalResult {
        if (reset.getBasis() != Basis::Z) {
          return reset.emitOpError() << "resets in basis '" << stringifyBasis(reset.getBasis()) << "', which "
                                     << passName << " does not support";
        }
        return success();
      })
      .Default([&](Operation* other) { return other->emitOpError() << "is not supported by " << passName; });
}

/// Creates the QIR pointer of the static qubit `index` at the current insertion point:
///
/// ```mlir
/// %0 = llvm.mlir.constant(42 : i64) : i64
/// %1 = llvm.inttoptr %0 : i64 to !llvm.ptr
/// ```
static Value createQubitPtr(OpBuilder& builder, Location loc, int64_t index) {
  auto i64Type = builder.getI64Type();
  auto ptrType = LLVM::LLVMPointerType::get(builder.getContext());

  auto constantOp = LLVM::ConstantOp::create(builder, loc, i64Type, builder.getI64IntegerAttr(index));
  return LLVM::IntToPtrOp::create(builder, loc, ptrType, {constantOp});
}

/// To be used in a rewrite pattern.
static InFlightDiagnostic emitMissingQIRDeclError(Operation* op, StringRef name) {
  return op->emitError() << "missing required declaration of QIR function: '" << name << "'";
}

static std::tuple<int64_t, Operation*> countRecordsAndGetFirstRecordOp(func::FuncOp funcOp) {
  int64_t recordCount = 0;
  Operation* firstRecordOp = nullptr;

  funcOp.walk([&](Operation* op) {
    if (isa<qcc::aux::RecordMemRefOp, qcc::aux::RecordIntOp>(op)) {
      recordCount++;
      if (firstRecordOp == nullptr) {
        firstRecordOp = op;
      }
    }
  });
  return std::make_tuple(recordCount, firstRecordOp);
}

static void insertRtTupleRecord(func::FuncOp funcOp, Operation* firstRecordOp, int64_t recordCount) {
  StringRef labelName = qcc::qirDummyLabelGlobalSymbolName;
  OpBuilder builder(funcOp.getContext());
  Location loc = firstRecordOp->getLoc();

  builder.setInsertionPoint(firstRecordOp);

  Value countVal = LLVM::ConstantOp::create(builder, loc, builder.getI64Type(), builder.getI64IntegerAttr(recordCount));
  auto addressOf = LLVM::AddressOfOp::create(builder, loc, LLVM::LLVMPointerType::get(builder.getContext()), labelName);

  LLVM::CallOp::create(builder, loc, TypeRange(), qirRtTupleRecordOutput, ValueRange{countVal, addressOf});
}

/// Replaces the gate `op` by a call of the QIR QIS function `qisName`. We rely on the fact that the signature of the
/// QIS function fits: the angles first, then the qubits in the order of the gate (the control first).
static LogicalResult replaceByQISCall(Operation* op, StringRef qisName, ValueRange params, ValueRange qubitPtrs,
                                      ConversionPatternRewriter& rewriter) {
  assert(!qisName.empty() && "the preconditions rule out gates outside the native gate set");
  auto fnDecl = op->getParentOfType<ModuleOp>().lookupSymbol<LLVM::LLVMFuncOp>(qisName);
  if (!fnDecl) {
    return emitMissingQIRDeclError(op, qisName);
  }

  SmallVector<Value> args(params);
  llvm::append_range(args, qubitPtrs);
  LLVM::CallOp::create(rewriter, op->getLoc(), fnDecl, args);
  rewriter.eraseOp(op);
  return success();
}

namespace {

struct QRefToQIRTypeConverter final : LLVMTypeConverter {
  explicit QRefToQIRTypeConverter(MLIRContext* ctx) : LLVMTypeConverter(ctx) {
    addConversion([ctx](QubitRefType) { return LLVM::LLVMPointerType::get(ctx); });
  }
};

/// Replaces each reference by the QIR pointer of its static qubit.
struct StaticRefLowering final : OpConversionPattern<StaticRefOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(StaticRefOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    SmallVector<Value> ptrs;
    for (const int64_t index : op.getIndices()) {
      ptrs.push_back(createQubitPtr(rewriter, op.getLoc(), index));
    }
    rewriter.replaceOp(op, ptrs);
    return success();
  }
};

struct SingleLowering final : OpConversionPattern<qref::SingleOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qref::SingleOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    return replaceByQISCall(op, getQISFunction(op.getGateKind()), adaptor.getParams(), adaptor.getQubit(), rewriter);
  }
};

struct PairLowering final : OpConversionPattern<qref::PairOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qref::PairOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    return replaceByQISCall(op, getQISFunction(op.getGateKind()), adaptor.getParams(),
                            ValueRange{adaptor.getLhs(), adaptor.getRhs()}, rewriter);
  }
};

struct MeasureLowering final : OpConversionPattern<qref::MeasureOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qref::MeasureOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    assert(op.getBasis() == Basis::Z && "the preconditions rule out other bases");
    auto moduleOp = op->getParentOfType<ModuleOp>();

    auto mzFnDecl = moduleOp.lookupSymbol<LLVM::LLVMFuncOp>(qcc::qirQisMZ);
    if (!mzFnDecl) {
      return emitMissingQIRDeclError(op, qcc::qirQisMZ);
    }

    auto readFnDecl = moduleOp.lookupSymbol<LLVM::LLVMFuncOp>(qcc::qirRtReadResult);
    if (!readFnDecl) {
      return emitMissingQIRDeclError(op, qcc::qirRtReadResult);
    }

    // TODO: This holds only for HiSEP-Q.
    // NOTE: Qubit and result pointer share the same index.
    Value qubitPtr = adaptor.getQubit();
    Value resultPtr = qubitPtr;

    LLVM::CallOp::create(rewriter, op.getLoc(), mzFnDecl, ValueRange{qubitPtr, resultPtr});
    auto callReadOp = LLVM::CallOp::create(rewriter, op.getLoc(), readFnDecl, ValueRange{resultPtr});

    rewriter.replaceOp(op, callReadOp);
    return success();
  }
};

struct ResetLowering final : OpConversionPattern<qref::ResetOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(qref::ResetOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    assert(op.getBasis() == Basis::Z && "the preconditions rule out other bases");
    auto moduleOp = op->getParentOfType<ModuleOp>();

    auto resetFnDecl = moduleOp.lookupSymbol<LLVM::LLVMFuncOp>(qcc::qirQisReset);
    if (!resetFnDecl) {
      return emitMissingQIRDeclError(op, qcc::qirQisReset);
    }

    LLVM::CallOp::create(rewriter, op.getLoc(), resetFnDecl, ValueRange{adaptor.getQubit()});
    rewriter.eraseOp(op);
    return success();
  }
};

struct RecordIntLowering : public OpConversionPattern<aux::RecordIntOp> {
  using OpConversionPattern<aux::RecordIntOp>::OpConversionPattern;

  LogicalResult matchAndRewrite(aux::RecordIntOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    auto loc = op.getLoc();
    StringRef labelName = qcc::qirDummyLabelGlobalSymbolName;

    auto addressOf =
        LLVM::AddressOfOp::create(rewriter, loc, LLVM::LLVMPointerType::get(rewriter.getContext()), labelName);

    Type ty = op.getValue().getType();

    llvm::StringRef callee;
    if (ty.isInteger(1)) {
      callee = qirRtBoolRecordOutput;
    } else if (ty.isInteger(64)) {
      callee = qirRtIntRecordOutput;
    } else {
      return failure();
    }

    LLVM::CallOp::create(rewriter, loc, TypeRange(), callee, ValueRange{adaptor.getValue(), addressOf});

    rewriter.eraseOp(op);
    return success();
  }
};

struct RecordMemrefLowering : public OpConversionPattern<aux::RecordMemRefOp> {
  using OpConversionPattern<aux::RecordMemRefOp>::OpConversionPattern;

  LogicalResult matchAndRewrite(aux::RecordMemRefOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    auto loc = op.getLoc();
    auto* ctx = rewriter.getContext();
    StringRef labelName = qcc::qirDummyLabelGlobalSymbolName;

    // 1. Get the address representation of your dummy label
    auto addressOf = LLVM::AddressOfOp::create(rewriter, loc, LLVM::LLVMPointerType::get(ctx), labelName);

    // 2. Extract the compile-time static size from the original memref operand
    MemRefType memrefType = cast<MemRefType>(op.getValue().getType());
    int64_t staticSize = memrefType.getDimSize(0);

    // 3. Emit the runtime function tracking the size of the array using pure LLVM constants
    auto i64Type = rewriter.getI64Type();
    Value totalElementsConst = LLVM::ConstantOp::create(rewriter, loc, i64Type, rewriter.getI64IntegerAttr(staticSize));

    LLVM::CallOp::create(rewriter, loc, TypeRange(), qirRtArrayRecordOutput, ValueRange{totalElementsConst, addressOf});

    // 4. Extract the aligned pointer from the LLVM memref descriptor struct (adaptor value)
    // Under the MLIR type converter, a standard MemRef maps to an LLVM struct
    // where index 1 is the aligned data pointer.
    Value memrefDescriptor = adaptor.getValue();
    Value alignedPtr = LLVM::ExtractValueOp::create(rewriter, loc, memrefDescriptor, 1);

    // 5. Sequentially emit GEP and Load operations for each index using pure LLVM Dialect
    for (int64_t i = 0; i < staticSize; ++i) {
      // Create a compile-time index for GEP (GepOp expects i32 or i64 attributes/values)
      Value llvmIndex = LLVM::ConstantOp::create(rewriter, loc, i64Type, rewriter.getI64IntegerAttr(i));

      // Calculate the specific element address: ptr = alignedPtr + i
      auto elementPtr = LLVM::GEPOp::create(rewriter, loc, alignedPtr.getType(), memrefType.getElementType(),
                                            alignedPtr, ValueRange{llvmIndex});

      // Load the value out of that calculated element pointer
      auto elementValue = LLVM::LoadOp::create(rewriter, loc, memrefType.getElementType(), elementPtr);

      // Call the QIR runtime function for this specific element
      LLVM::CallOp::create(rewriter, loc, TypeRange(), qirRtIntRecordOutput, ValueRange{elementValue, addressOf});
    }

    rewriter.eraseOp(op);
    return success();
  }
};

} // namespace

namespace qcc {

#define GEN_PASS_DEF_CONVERTQREFTOQIR
#include "qcc/Conversion/ToQIR/ToQIR.h.inc"

namespace {

struct ConvertQRefToQIR final : impl::ConvertQRefToQIRBase<ConvertQRefToQIR> {
  using ConvertQRefToQIRBase::ConvertQRefToQIRBase;

protected:
  void runOnOperation() override {
    func::FuncOp funcOp = getOperation();
    auto* ctx = funcOp.getContext();

    if (failed(checkPreconditions())) {
      return signalPassFailure();
    }

    // The precondition check above ensures that only entry point functions hold qubits.
    if (!isEntryPoint(funcOp)) {
      return;
    }

    if (failed(setEntryPointAttrs())) {
      return signalPassFailure();
    }

    if (failed(insertRtInit())) {
      return signalPassFailure();
    }

    auto [recordCount, firstRecordOp] = countRecordsAndGetFirstRecordOp(funcOp);
    if (recordCount > 1 && firstRecordOp != nullptr) {
      insertRtTupleRecord(funcOp, firstRecordOp, recordCount);
    };

    ConversionTarget target(*ctx);
    target.addLegalDialect<LLVM::LLVMDialect>();
    target.addIllegalDialect<qref::QRefDialect>();
    target.addIllegalDialect<qcc::aux::AuxDialect>();
    target.addIllegalOp<StaticRefOp>();

    QRefToQIRTypeConverter typeConverter(ctx);
    RewritePatternSet patterns(ctx);
    patterns.add<StaticRefLowering, SingleLowering, PairLowering, MeasureLowering, ResetLowering, RecordIntLowering,
                 RecordMemrefLowering>(typeConverter, ctx);

    // TODO: This used to reconcile unrealized conversion casts for us. But it
    // seems wrong to run it at the function scope. See issue
    // https://github.com/FullStaQD/compiler/issues/130.
    // populateFinalizeMemRefToLLVMConversionPatterns(typeConverter, patterns);

    if (failed(applyPartialConversion(funcOp, target, std::move(patterns)))) {
      return signalPassFailure();
    }
  }

private:
  /// Checks that only entry points hold qubit references, that every qubit is a static qubit used only by qref ops,
  /// and that these ops have QIR counterparts.
  LogicalResult checkPreconditions() {
    func::FuncOp funcOp = getOperation();
    if (llvm::any_of(funcOp.getArgumentTypes(), isQubitRefOrArray)) {
      return funcOp.emitOpError() << "has a qubit reference argument, which " << getArgument() << " does not support";
    }

    const bool entryPoint = isEntryPoint(funcOp);
    const WalkResult result = funcOp.walk<WalkOrder::PreOrder>([&](Operation* op) {
      if (!holdsQubitRefs(op)) {
        return WalkResult::advance();
      }
      if (!entryPoint) {
        op->emitOpError() << "uses qubit references outside an entry point, which " << getArgument()
                          << " does not support";
        return WalkResult::interrupt();
      }
      if (isa<StaticRefOp>(op)) {
        return WalkResult::advance();
      }
      if (isa_and_present<qref::QRefDialect>(op->getDialect())) {
        return succeeded(checkSupported(op, getArgument())) ? WalkResult::advance() : WalkResult::interrupt();
      }
      op->emitOpError() << "is not supported by " << getArgument() << " on qubit references";
      return WalkResult::interrupt();
    });
    return failure(result.wasInterrupted());
  }

  LogicalResult insertRtInit() {
    func::FuncOp funcOp = getOperation();
    auto moduleOp = funcOp->getParentOfType<ModuleOp>();
    auto* ctx = funcOp.getContext();

    auto initFnDecl = moduleOp.lookupSymbol<LLVM::LLVMFuncOp>(qcc::qirRtInit);

    if (!initFnDecl) {
      return emitMissingQIRDeclError(funcOp, qcc::qirRtInit);
    }

    auto loc = funcOp.getLoc();
    OpBuilder builder(ctx);
    builder.setInsertionPointToStart(&funcOp.front());

    auto ptrType = LLVM::LLVMPointerType::get(ctx);
    auto nullPtr = LLVM::ZeroOp::create(builder, loc, ptrType);
    LLVM::CallOp::create(builder, loc, initFnDecl, ValueRange{nullPtr});

    return llvm::success();
  }

  /// The highest index of a static qubit plus one.
  int64_t getRequiredNumQubits() {
    const func::FuncOp funcOp = getOperation();
    int64_t numQubits = 0;
    funcOp->walk([&](StaticRefOp op) -> void {
      for (const int64_t index : op.getIndices()) {
        numQubits = std::max(numQubits, index + 1);
      }
    });
    return numQubits;
  }

  /// Attaches all the relevant QIR attributes (like `required_num_qubits`) to the function.
  LogicalResult setEntryPointAttrs() {
    func::FuncOp funcOp = getOperation();
    OpBuilder builder(funcOp.getContext());

    auto requiredNumQubits = getRequiredNumQubits();
    auto requiredNumResults = requiredNumQubits; // TODO: holds only for HiSEP-Q!

    auto getKV = [&](StringRef key, StringRef value) {
      return builder.getArrayAttr({builder.getStringAttr(key), builder.getStringAttr(value)});
    };

    // Assuming numQubits and numResults are variables
    const SmallVector<Attribute> passthrough = {
        builder.getStringAttr(qcc::qirEntryPointPassthrough), getKV("output_labeling_schema", "schema_id"),
        getKV("qir_profiles", "adaptive_profile"), getKV("required_num_qubits", std::to_string(requiredNumQubits)),
        getKV("required_num_results", std::to_string(requiredNumResults))};

    // We set `llvm.passthrough` rather than `passthrough` (`qcc::passthroughAttrName`) because only with the `llvm`
    // prefix it is forwarded as `passthrough` when lowering to `llvm.func`. Otherwise it is silently dropped.
    funcOp->setAttr("llvm." + qcc::passthroughAttrName.str(), builder.getArrayAttr(passthrough));

    return success();
  }
};

} // namespace
} // namespace qcc
