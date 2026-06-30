// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/Aux_/AuxOutputRecording.h" // IWYU pragma: keep

#include "qcc/Dialect/Aux_/IR/Aux_.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/Support/LLVM.h"
#include "mlir/Transforms/DialectConversion.h"

#include <llvm/Support/Casting.h>
#include <mlir/Support/WalkResult.h>

namespace qcc {

#define GEN_PASS_DEF_AUXOUTPUTRECORDING
#include "qcc/Conversion/Aux_/AuxOutputRecording.h.inc"

using namespace mlir;

namespace {

struct AuxOutputRecording final : public impl::AuxOutputRecordingBase<AuxOutputRecording> {

  using AuxOutputRecordingBase<AuxOutputRecording>::AuxOutputRecordingBase;

protected:
  void runOnOperation() override {
    auto module = cast<mlir::ModuleOp>(getOperation());

    auto walkResult = module.walk([&](func::FuncOp funcOp) {
      if (!funcOp->hasAttr("qcc.entry_point")) {
        return WalkResult::advance();
      }

      if (funcOp.getNumResults() == 0) {
        return WalkResult::advance();
      }

      if (funcOp.getBody().getBlocks().size() != 1) {
        funcOp.emitError("Expected exactly one block in the function.");
        return WalkResult::interrupt();
      }

      // Build a new function type with void return type
      // Keep the original argument types, drop results.
      auto oldType = funcOp.getFunctionType();
      auto newType = FunctionType::get(funcOp->getContext(), oldType.getInputs(), {});

      funcOp.setType(newType);

      auto& body = funcOp.getBody().front();
      auto retOp = cast<func::ReturnOp>(body.getTerminator());
      auto oldReturnOperands = retOp.getOperands();

      OpBuilder builder(retOp);

      auto loc = retOp.getLoc();
      for (Value v : oldReturnOperands) {
        Type ty = v.getType();
        if (ty.isInteger()) {
          aux::RecordIntOp::create(builder, loc, v);
        } else {
          // TODO: Add support for other types as needed.
          funcOp.emitError("Non-integer return types are not supported.");
          return WalkResult::interrupt();
        }
      }
      // Remove the old return with values and replace with a void return
      retOp.erase();
      builder.setInsertionPointToEnd(&body);
      func::ReturnOp::create(builder, loc);
      return WalkResult::advance();
    });

    if (walkResult.wasInterrupted()) {
      return signalPassFailure();
    }
  };
};
} // namespace
} // namespace qcc
