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
#include "qcc/Dialect/Aux_/IR/Aux_.h"

#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Conversion/MemRefToLLVM/MemRefToLLVM.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/LLVMIR/LLVMTypes.h"
#include "mlir/Dialect/QC/IR/QCDialect.h"
#include "mlir/Dialect/QC/IR/QCInterfaces.h"
#include "mlir/Dialect/QC/IR/QCOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Support/LogicalResult.h"
#include "mlir/Support/WalkResult.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/TypeSwitch.h"

#include <mlir/Dialect/Arith/IR/Arith.h>
#include <mlir/Dialect/MemRef/IR/MemRef.h>
#include <mlir/Dialect/SCF/IR/SCF.h>
#include <mlir/Pass/Pass.h>

using namespace mlir;
using namespace qcc;

/// Maps any of the (unitary) gate-ops to their QIR QIS function declaration if possible.
///
/// Returns an empty string upon failure. Succeeds iff the gate is among the supported native gate set.
///
/// TODO: The native gate set is currently hardcoded.
static StringRef mapUnitaryToQIS(qc::UnitaryOpInterface unitaryOp) {
  if (unitaryOp.getNumControls() == 0) {
    return llvm::TypeSwitch<Operation*, StringRef>(unitaryOp)
        .Case<qc::XOp>([](auto) { return qcc::qirQisX; })
        .Case<qc::HOp>([](auto) { return qcc::qirQisH; })
        .Case<qc::RZOp>([](auto) { return qcc::qirQisRZ; })
        // The phase gate P(θ) differs from RZ(θ) only by a global phase,
        // which does not affect measurement outcomes. QIR has no native
        // phase gate, so we lower P to RZ.
        .Case<qc::POp>([](auto) { return qcc::qirQisRZ; })
        .Case<qc::TOp>([](auto) { return qcc::qirQisT; })
        .Case<qc::TdgOp>([](auto) { return qcc::qirQisTdg; })
        .Case<qc::SOp>([](auto) { return qcc::qirQisS; })
        .Case<qc::SdgOp>([](auto) { return qcc::qirQisSdg; })
        .Default([](auto) { return ""; });
  }

  if (unitaryOp.getNumControls() == 1) {
    auto ctrlOp = cast<qc::CtrlOp>(unitaryOp);
    if (ctrlOp.getNumBodyUnitaries() != 1) {
      return "";
    }
    auto bodyOp = ctrlOp.getBodyUnitary(0);

    return llvm::TypeSwitch<Operation*, StringRef>(bodyOp)
        .Case<qc::XOp>([](auto) { return qcc::qirQisCX; })
        .Default([](auto) { return ""; });
  }

  return "";
}

/// Converts a qubit to an llvm ptr.
///
/// We assume that it was created by a static op, like this:
///
/// ```mlir
/// %0 = qc.static 42 : !qc.qubit
/// ```
///
/// it then adds the following for each qubit at the current insertion point (and leaves the `qc.static` as is):
///
/// ```mlir
/// %1 = llvm.mlir.constant(42 : i64) : i64
/// %2 = llvm.inttoptr %1 : i64 to !llvm.ptr
/// ```
static Value qubitToPtr(OpBuilder& builder, Value qubitValue) {
  auto* defOp = qubitValue.getDefiningOp();
  assert(defOp && isa<qc::StaticOp>(defOp) &&
         "The pass assumes that all qubits come from static allocations (in particular no function args).");
  auto alloc = cast<qc::StaticOp>(defOp);

  auto index = static_cast<int64_t>(alloc.getIndex());

  auto i64Type = builder.getI64Type();
  auto ptrType = LLVM::LLVMPointerType::get(builder.getContext());

  auto constantOp = LLVM::ConstantOp::create(builder, defOp->getLoc(), i64Type, builder.getI64IntegerAttr(index));
  auto ptrOp = LLVM::IntToPtrOp::create(builder, defOp->getLoc(), ptrType, {constantOp});

  return ptrOp;
}

/// Applies `qubitToPtr` to each qubit of the given list and returns the result.
static SmallVector<Value> qubitsToPtrs(OpBuilder& builder, ValueRange qubitValues) {
  SmallVector<Value> ptrValues;
  ptrValues.reserve(qubitValues.size());

  for (auto qubitValue : qubitValues) {
    auto ptrOp = qubitToPtr(builder, qubitValue);
    ptrValues.push_back(ptrOp);
  }

  return ptrValues;
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

namespace {

struct QCToQIRTypeConverter final : LLVMTypeConverter {
  explicit QCToQIRTypeConverter(MLIRContext* ctx) : LLVMTypeConverter(ctx) {
    addConversion([ctx](qc::QubitType) { return LLVM::LLVMPointerType::get(ctx); });
  }
};

struct MeasureLowering : public OpConversionPattern<qc::MeasureOp> {
  using OpConversionPattern<qc::MeasureOp>::OpConversionPattern;

  LogicalResult matchAndRewrite(qc::MeasureOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
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
    auto qubit = op.getQubit();
    auto qubitPtr = qubitToPtr(rewriter, qubit);
    auto resultPtr = qubitToPtr(rewriter, qubit);

    LLVM::CallOp::create(rewriter, op.getLoc(), mzFnDecl, {qubitPtr, resultPtr});
    auto callReadOp = LLVM::CallOp::create(rewriter, op.getLoc(), readFnDecl, {resultPtr});

    rewriter.replaceOp(op, callReadOp);
    return success();
  }
};

struct ResetLowering : public OpConversionPattern<qc::ResetOp> {
  using OpConversionPattern<qc::ResetOp>::OpConversionPattern;

  LogicalResult matchAndRewrite(qc::ResetOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    auto moduleOp = op->getParentOfType<ModuleOp>();

    auto resetFnDecl = moduleOp.lookupSymbol<LLVM::LLVMFuncOp>(qcc::qirQisReset);
    if (!resetFnDecl) {
      return emitMissingQIRDeclError(op, qcc::qirQisReset);
    }

    auto qubitPtr = qubitToPtr(rewriter, op.getQubit());
    LLVM::CallOp::create(rewriter, op.getLoc(), resetFnDecl, ValueRange{qubitPtr});
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

/// We rely on the fact that the signature of qc gates and the corresponding QIR QIS function fits.
struct UnitaryLowering : public ConversionPattern {
  UnitaryLowering(TypeConverter& converter, MLIRContext* ctx)
      : ConversionPattern(converter, MatchAnyOpTypeTag(), 1, ctx) {}

  LogicalResult matchAndRewrite(Operation* op, ArrayRef<Value> /*operands*/,
                                ConversionPatternRewriter& rewriter) const override {
    auto unitaryOp = dyn_cast<qc::UnitaryOpInterface>(op);
    if (!unitaryOp || !isa<qc::QCDialect>(op->getDialect())) {
      return failure();
    }

    auto moduleOp = op->getParentOfType<ModuleOp>();

    auto qisName = mapUnitaryToQIS(unitaryOp);
    auto fnDecl = moduleOp.lookupSymbol<LLVM::LLVMFuncOp>(qisName);
    if (!fnDecl) {
      return emitMissingQIRDeclError(unitaryOp, qisName);
    }

    auto args = llvm::to_vector(unitaryOp.getParameters());

    auto controlPtrs = qubitsToPtrs(rewriter, unitaryOp.getControls());
    auto targetPtrs = qubitsToPtrs(rewriter, unitaryOp.getTargets());
    args.append(controlPtrs);
    args.append(targetPtrs);

    LLVM::CallOp::create(rewriter, op->getLoc(), fnDecl, args);
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

#define GEN_PASS_DEF_CONVERTQCTOQIR
#include "qcc/Conversion/ToQIR/ToQIR.h.inc"

namespace {

struct ConvertQCToQIR final : impl::ConvertQCToQIRBase<ConvertQCToQIR> {
  using ConvertQCToQIRBase::ConvertQCToQIRBase;

protected:
  void runOnOperation() override {
    func::FuncOp funcOp = getOperation();
    auto* ctx = funcOp.getContext();

    // TODO: assume that only entrypoints contain quantum ops.
    if (!funcOp->hasAttr(qcc::entryPointAttrName)) {
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
    target.addIllegalDialect<qc::QCDialect>();
    target.addIllegalDialect<qcc::aux::AuxDialect>();
    target.addLegalOp<qc::StaticOp>(); // take care of slightly later.

    QCToQIRTypeConverter typeConverter(ctx);
    RewritePatternSet patterns(ctx);
    patterns.add<UnitaryLowering, MeasureLowering, RecordIntLowering, RecordMemrefLowering, ResetLowering>(
        typeConverter, ctx);

    // TODO: This used to reconcile unrealized conversion casts for us. But it
    // seems wrong to run it at the function scope. See issue
    // https://github.com/FullStaQD/compiler/issues/130.
    // populateFinalizeMemRefToLLVMConversionPatterns(typeConverter, patterns);

    if (failed(applyPartialConversion(funcOp, target, std::move(patterns)))) {
      return signalPassFailure();
    }

    removeQCStaticOps();
  }

private:
  LogicalResult insertRtInit() {
    func::FuncOp funcOp = getOperation();
    auto moduleOp = funcOp->getParentOfType<ModuleOp>();
    auto* ctx = funcOp.getContext();

    auto initFnDecl = moduleOp.lookupSymbol<LLVM::LLVMFuncOp>(qcc::qirRtInit);

    if (!initFnDecl) {
      return emitMissingQIRDeclError(moduleOp, qcc::qirRtInit);
    }

    auto loc = funcOp.getLoc();
    OpBuilder builder(ctx);
    builder.setInsertionPointToStart(&funcOp.front());

    auto ptrType = LLVM::LLVMPointerType::get(ctx);
    auto nullPtr = LLVM::ZeroOp::create(builder, loc, ptrType);
    LLVM::CallOp::create(builder, loc, initFnDecl, ValueRange{nullPtr});

    return llvm::success();
  }

  uint64_t getRequiredNumQubits() {
    const func::FuncOp funcOp = getOperation();
    uint64_t numQubits = 0;
    funcOp->walk([&](qc::StaticOp op) -> void {
      auto index = op.getIndex();
      numQubits = std::max(numQubits, index + 1);
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

    funcOp->setAttr(qcc::passthroughAttrName, builder.getArrayAttr(passthrough));

    return success();
  }

  void removeQCStaticOps() {
    getOperation()->walk([](qc::StaticOp op) { op.erase(); });
  }
};

} // namespace
} // namespace qcc
