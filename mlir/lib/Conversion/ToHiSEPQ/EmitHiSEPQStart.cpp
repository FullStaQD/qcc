// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Constants.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/LLVMIR/LLVMTypes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LogicalResult.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

/// Whether `funcOp` carries the `entry_point` passthrough attribute.
static bool isEntryPointFunc(LLVM::LLVMFuncOp funcOp) {
  auto passthrough = funcOp->getAttrOfType<ArrayAttr>(qcc::passthroughAttrName);
  if (!passthrough) {
    return false;
  }

  return llvm::any_of(passthrough, [](Attribute attr) {
    auto strAttr = dyn_cast<StringAttr>(attr);
    return strAttr && strAttr.getValue() == qcc::qirEntryPointPassthrough;
  });
}

namespace qcc {

#define GEN_PASS_DEF_EMITHISEPQSTART
#include "qcc/Conversion/ToHiSEPQ/ToHiSEPQ.h.inc"

namespace {

struct EmitHiSEPQStart final : impl::EmitHiSEPQStartBase<EmitHiSEPQStart> {
  using EmitHiSEPQStartBase::EmitHiSEPQStartBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();

    FailureOr<LLVM::LLVMFuncOp> entryPoint = getEntryPoint(moduleOp);
    if (failed(entryPoint)) {
      return signalPassFailure();
    }

    emitStartFunc(moduleOp, *entryPoint);
  }

private:
  /// Returns the entry point of the module. Fails if not exactly one function
  /// is tagged, as the hardware boots at a single address.
  static FailureOr<LLVM::LLVMFuncOp> getEntryPoint(ModuleOp moduleOp) {
    LLVM::LLVMFuncOp entryPoint;

    for (auto funcOp : moduleOp.getOps<LLVM::LLVMFuncOp>()) {
      if (!isEntryPointFunc(funcOp)) {
        continue;
      }
      if (entryPoint) {
        return funcOp.emitError("expected at most one function tagged as the entry point, but found '")
               << entryPoint.getName() << "' and '" << funcOp.getName()
               << "'"; // FIXME: if funcOp emits the error do we really need to print the name?
      }
      entryPoint = funcOp;
    }

    if (!entryPoint) {
      return moduleOp->emitError("did not find any entry point");
    }

    return entryPoint;
  }

  /// Emits `_start`, which supersedes `entryPoint` as the entry point of the hardware.
  static void emitStartFunc(ModuleOp moduleOp, LLVM::LLVMFuncOp entryPoint) {
    OpBuilder builder(moduleOp.getContext());
    builder.setInsertionPointToEnd(moduleOp.getBody());
    Location loc = entryPoint.getLoc();

    auto stackTopType = LLVM::LLVMArrayType::get(builder.getI8Type(), 0);
    auto stackTop = LLVM::GlobalOp::create(builder, loc, stackTopType, /*isConstant=*/true, LLVM::Linkage::External,
                                           "__stack_top", /*value=*/Attribute());

    auto startFuncType = LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(builder.getContext()), {});
    auto startFunc = LLVM::LLVMFuncOp::create(builder, loc, "_start", startFuncType);
    builder.setInsertionPointToStart(startFunc.addEntryBlock(builder));

    Value stackTopAddr = LLVM::AddressOfOp::create(builder, loc, stackTop);
    Value entryAddr = LLVM::AddressOfOp::create(builder, loc, entryPoint);

    auto asmDialect = LLVM::AsmDialectAttr::get(builder.getContext(), LLVM::AsmDialect::AD_ATT);
    LLVM::InlineAsmOp::create(builder, loc, /*resultTypes=*/TypeRange(),
                              /*operands=*/ValueRange{stackTopAddr, entryAddr},
                              /*asm_string=*/"mv sp, $0\njalr ra, 0($1)\n1:\nj 1b",
                              /*constraints=*/"r,r", /*has_side_effects=*/true,
                              /*is_align_stack=*/false, LLVM::TailCallKind::None,
                              /*asm_dialect=*/asmDialect, /*operand_attrs=*/ArrayAttr());

    LLVM::UnreachableOp::create(builder, loc);
  }
};

} // namespace
} // namespace qcc
