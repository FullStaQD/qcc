// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/ToQIR/Constants.h"
#include "qcc/Conversion/ToQIR/ToQIR.h"

#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/LLVMIR/LLVMTypes.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"

using namespace mlir;

namespace qcc {

#define GEN_PASS_DEF_PREPTOQIR
#include "qcc/Conversion/ToQIR/ToQIR.h.inc"

namespace {

struct PrepToQIR final : public impl::PrepToQIRBase<PrepToQIR> {
  using impl::PrepToQIRBase<PrepToQIR>::PrepToQIRBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();
    OpBuilder builder(ctx);

    // Runtime functions:
    createVoidFnDecl(qcc::qirRtInit, 1);
    createRtBoolRecordOutputDecl();
    createRtIntRecordOutputDecl();
    createRtReadResultDecl();

    // QIS:
    auto fnMZ = createVoidFnDecl(qcc::qirQisMZ, 2);
    fnMZ.setArgAttr(1, "llvm.writeonly", builder.getUnitAttr());
    fnMZ->setAttr("passthrough", builder.getStrArrayAttr({"irreversible"}));
    createVoidFnDecl(qcc::qirQisH, 1);
    createVoidFnDecl(qcc::qirQisX, 1);
    createVoidFnDecl(qcc::qirQisS, 1);
    createVoidFnDecl(qcc::qirQisSdg, 1);
    createVoidFnDecl(qcc::qirQisT, 1);
    createVoidFnDecl(qcc::qirQisTdg, 1);
    createVoidFnDecl(qcc::qirQisCX, 2);
    createF64PtrFnDecl(qcc::qirQisRZ);

    addQIRModuleFlags();

    addGlobalDummyLabel();
  }

private:
  /// Inserts `llvm.func` with signature `fnName(ptr, ptr, ...) -> void`.
  LLVM::LLVMFuncOp createVoidFnDecl(StringRef fnName, int numPtrs) {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();
    OpBuilder builder(ctx);
    builder.setInsertionPointToEnd(moduleOp.getBody());

    auto ptrType = LLVM::LLVMPointerType::get(ctx);
    const SmallVector<Type, 2> argTypes(numPtrs, ptrType);
    auto fnType = LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(ctx), argTypes);

    auto fnDecl = LLVM::LLVMFuncOp::create(builder, moduleOp.getLoc(), fnName, fnType);

    return fnDecl;
  }

  /// Inserts `llvm.func` with signature `__quantum__rt__read_result(ptr readonly) -> void`.
  void createRtReadResultDecl() {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();
    OpBuilder builder(ctx);
    builder.setInsertionPointToEnd(moduleOp.getBody());

    auto ptrType = LLVM::LLVMPointerType::get(ctx);
    auto i1Type = IntegerType::get(ctx, 1);
    auto fnType = LLVM::LLVMFunctionType::get(i1Type, {ptrType});

    auto fnDecl = LLVM::LLVMFuncOp::create(builder, moduleOp.getLoc(), qcc::qirRtReadResult, fnType);
    fnDecl.setArgAttr(0, "llvm.readonly", builder.getUnitAttr());
  }

  /// Inserts `llvm.func` with signature `__quantum__rt__bool_record_output(i1, ptr) -> void`.
  void createRtBoolRecordOutputDecl() {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();
    OpBuilder builder(ctx);
    builder.setInsertionPointToEnd(moduleOp.getBody());

    auto voidType = LLVM::LLVMVoidType::get(ctx);
    auto i1Type = IntegerType::get(ctx, 1);
    auto ptrType = LLVM::LLVMPointerType::get(ctx);
    auto fnType = LLVM::LLVMFunctionType::get(voidType, {i1Type, ptrType});

    LLVM::LLVMFuncOp::create(builder, moduleOp.getLoc(), qcc::qirRtBoolRecordOutput, fnType);
  }

  /// Inserts `llvm.func` with signature `__quantum__rt__int_record_output(i64, ptr) -> void`.
  void createRtIntRecordOutputDecl() {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();
    OpBuilder builder(ctx);
    builder.setInsertionPointToEnd(moduleOp.getBody());

    auto voidType = LLVM::LLVMVoidType::get(ctx);
    auto i64Type = IntegerType::get(ctx, 64);
    auto ptrType = LLVM::LLVMPointerType::get(ctx);
    auto fnType = LLVM::LLVMFunctionType::get(voidType, {i64Type, ptrType});

    LLVM::LLVMFuncOp::create(builder, moduleOp.getLoc(), qcc::qirRtIntRecordOutput, fnType);
  }

  /// Creates the module flags which specify the capabilities which the backend needs to support.
  ///
  /// Of course we in turn also have to ensure that our output does not go beyond those capabilities.
  ///
  /// TODO: Currently we hardcode the capabilities. In the future we have to query those (e.g. QDMI).
  void addQIRModuleFlags() {
    ModuleOp module = getOperation();
    auto* ctx = module.getContext();
    OpBuilder builder(ctx);
    builder.setInsertionPointToEnd(module.getBody());
    auto loc = module.getLoc();

    auto createFlag = [&](LLVM::ModFlagBehavior behavior, StringRef name, int32_t val) {
      // LLVM seems to normalize to i32 values. Even if we would use e.g. a i1
      // attribute for the boolean flags `mlir-translate` would still force it
      // to i32. Hence we stick to i32 always here.
      return LLVM::ModuleFlagAttr::get(ctx, behavior, builder.getStringAttr(name), builder.getI32IntegerAttr(val));
    };

    // NOTE: Missing flags are implicitly set to "false".
    const SmallVector<Attribute> flags = {
        createFlag(LLVM::ModFlagBehavior::Error, "qir_major_version", 2),
        createFlag(LLVM::ModFlagBehavior::Max, "qir_minor_version", 1),
        createFlag(LLVM::ModFlagBehavior::Error, "dynamic_qubit_management", 0),
        createFlag(LLVM::ModFlagBehavior::Error, "dynamic_result_management", 0),
        createFlag(LLVM::ModFlagBehavior::Error, "ir_functions", 1),
        // backwards_branching: 0: no, 1: only "unrollable" loops, 2: conditionally terminating loops
        createFlag(LLVM::ModFlagBehavior::Error, "backwards_branching", 1),
        createFlag(LLVM::ModFlagBehavior::Error, "multiple_target_branching", 0),
        createFlag(LLVM::ModFlagBehavior::Error, "multiple_return_points", 0)};

    LLVM::ModuleFlagsOp::create(builder, loc, builder.getArrayAttr(flags));
  }

  /// TODO: This is a workaround to satisfy QIRs need to always report a label
  /// when recording results. The input program currently has no notion of these
  /// labels hence we have to add one in an artificial way.
  void addGlobalDummyLabel() {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();
    OpBuilder builder(ctx);
    builder.setInsertionPointToEnd(moduleOp.getBody());

    auto loc = moduleOp->getLoc();
    auto i8Type = builder.getI8Type();
    StringRef label = "dummy_label";

    const unsigned size = label.size() + 1; // including null terminator '\0'
    auto i8ArrayType = LLVM::LLVMArrayType::get(i8Type, size);

    LLVM::GlobalOp::create(builder, loc, i8ArrayType,
                           /*isConstant=*/true, LLVM::Linkage::Internal, qcc::qirDummyLabelGlobalSymbolName,
                           builder.getStringAttr(label.str() + '\0') // Manual null terminator
    );
  }

  /// Inserts `llvm.func` with signature `fnName(f64, ptr) -> void`.
  ///
  /// Used for parametric single-qubit QIS gates whose first argument is a
  /// rotation angle (double-precision float) and second is the target qubit pointer.
  void createF64PtrFnDecl(StringRef fnName) {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();
    OpBuilder builder(ctx);
    builder.setInsertionPointToEnd(moduleOp.getBody());

    mlir::Type f64Type = builder.getF64Type(); // NOLINT(cppcoreguidelines-slicing)
    mlir::Type ptrType = LLVM::LLVMPointerType::get(ctx);

    auto fnType = LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(ctx), {f64Type, ptrType});

    LLVM::LLVMFuncOp::create(builder, moduleOp.getLoc(), fnName, fnType);
  }
};

} // namespace
} // namespace qcc
