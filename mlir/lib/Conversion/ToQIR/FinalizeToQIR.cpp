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
#include "qcc/Conversion/ToQIR/ToQIR.h"

#include "mlir/Conversion/FuncToLLVM/ConvertFuncToLLVM.h"
#include "mlir/Conversion/LLVMCommon/ConversionTarget.h"
#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Conversion/MemRefToLLVM/MemRefToLLVM.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Transforms/DialectConversion.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include <mlir/Conversion/ControlFlowToLLVM/ControlFlowToLLVM.h>
#include <mlir/Conversion/SCFToControlFlow/SCFToControlFlow.h>

using namespace mlir;

namespace {

struct CleanupFuncAttrs : public OpRewritePattern<func::FuncOp> {
  using OpRewritePattern<func::FuncOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(func::FuncOp funcOp, PatternRewriter& /*rewriter*/) const override {
    const OpBuilder builder(funcOp->getContext());

    if (funcOp->hasAttr(qcc::entryPointAttrName)) {
      funcOp->removeAttr(qcc::entryPointAttrName);
    }

    return failure();
  }
};

} // namespace

namespace qcc {

#define GEN_PASS_DEF_FINALIZETOQIR
#include "qcc/Conversion/ToQIR/ToQIR.h.inc"

namespace {

struct FinalizeToQIR final : public impl::FinalizeToQIRBase<FinalizeToQIR> {
  using FinalizeToQIRBase::FinalizeToQIRBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();

    // Cleanup func attrs.
    {
      RewritePatternSet patterns(ctx);
      patterns.add<CleanupFuncAttrs>(ctx);

      if (failed(applyPatternsGreedily(moduleOp, std::move(patterns)))) {
        signalPassFailure();
      }
    }

    // Finish conversion to LLVM.
    {
      LLVMConversionTarget target(*ctx);
      target.addLegalOp<ModuleOp>();

      const LLVMTypeConverter typeConverter(ctx);
      RewritePatternSet patterns(ctx);

      populateFuncToLLVMConversionPatterns(typeConverter, patterns);

      populateFinalizeMemRefToLLVMConversionPatterns(typeConverter, patterns);

      populateSCFToControlFlowConversionPatterns(patterns);
      cf::populateControlFlowToLLVMConversionPatterns(typeConverter, patterns);

      if (failed(applyFullConversion(moduleOp, target, std::move(patterns)))) {
        return signalPassFailure();
      }
    }
  }
};

} // namespace
} // namespace qcc
