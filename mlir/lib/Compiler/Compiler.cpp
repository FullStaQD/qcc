// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Compiler/Compiler.h"

#include "qcc/Conversion/AffineRaise/AffineRaise.h"
#include "qcc/Conversion/JaspToQC/JaspToQC.h"

#include "mlir/Conversion/AffineToStandard/AffineToStandard.h"
#include "mlir/Dialect/Affine/Transforms/Passes.h"
#include "mlir/Dialect/Bufferization/Transforms/Passes.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Linalg/Passes.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Transforms/Passes.h"

#include <llvm/Support/ErrorHandling.h>

/// Lower Qrisp to QC, QCO and standard MLIR dialects.
static void addLoweringQrisp(mlir::PassManager& pm);

namespace qcc {

void buildPipeline(mlir::PassManager& pm, const Target* target) {
  addLoweringQrisp(pm);
  target->addLoweringPasses(pm);
}

} // namespace qcc

static void addLoweringQrisp(mlir::PassManager& pm) {
  // Qrisp output contains a lot of functions that can be trivially inlined.
  pm.addPass(mlir::createInlinerPass());

  pm.addPass(qcc::createAddEntrypointToMain());

  // Lowering from JASP to QC
  // In addition to the obvious conversions, the rank-0 tensors
  // are converted to plain values (e.g. tensor<i64> becomes i64)
  // whenever possible.
  pm.addPass(qcc::createJaspToQC());

  // Convert `tensor.empty` to `bufferization.alloc_tensor`, which is expected by
  // bufferization.
  pm.addPass(mlir::bufferization::createEmptyTensorToAllocTensorPass());

  // Detensorization attempts to convert those rank-0-tensors to plain values
  // which have not been eliminated in the JaspToQC pass.
  // Aggressive mode ensures that some trivial `linalg.generic` ops are
  // unwrapped.
  mlir::LinalgDetensorizePassOptions detensorizeOptions;
  detensorizeOptions.aggressiveMode = true;
  pm.addNestedPass<mlir::func::FuncOp>(mlir::createLinalgDetensorizePass(detensorizeOptions));

  // Via Bufferization, we go from value semantics (tensor types) to
  // memory semantics (memref types). We want to make these changes in function signatures
  // as well, and allow for unknown (quantum) operations in the IR.
  mlir::bufferization::OneShotBufferizePassOptions bufferizeOptions;
  bufferizeOptions.allowUnknownOps = true;
  bufferizeOptions.allowReturnAllocsFromLoops = true;
  bufferizeOptions.bufferizeFunctionBoundaries = true;
  pm.addPass(mlir::bufferization::createOneShotBufferizePass(bufferizeOptions));

  // To facilitate data flow analysis, memory allocation is "hoisted out of loops" whenever possible.
  pm.addNestedPass<mlir::func::FuncOp>(mlir::bufferization::createBufferLoopHoistingPass());

  // Leftover `linalg` operations are converted to `affine` loops.
  pm.addNestedPass<mlir::func::FuncOp>(mlir::createConvertLinalgToAffineLoopsPass());

  // Convert `scf.while` loops into `scf.for` loops where possible, so that
  // they can subsequently be raised to `affine.for`.
  pm.addNestedPass<mlir::func::FuncOp>(qcc::createWhileToFor());

  // Raise `scf.for` loops to `affine.for` where the bounds and step permit it.
  pm.addNestedPass<mlir::func::FuncOp>(qcc::createTmpRaiseSCFToAffinePass());
  pm.addPass(mlir::createCanonicalizerPass());

  // Unroll affine loops.
  // TODO: We have to do this in this by parsing because the createAffineLoopUnroll function does not pass on the -1
  // factor (instead uses a value of 4, see https://github.com/llvm/llvm-project/issues/204801).
  // To deal with nested loops, we specify unroll-num-reps=10. This should be changed to a more robust solution in the
  // future.
  // In addition, to support the IQPE integration test, we need to perform a two-step unrolling.
  // See also issue https://github.com/FullStaQD/compiler/issues/111.
  mlir::affine::registerAffineLoopUnroll();
  if (failed(mlir::parsePassPipeline("func.func(affine-loop-unroll{unroll-factor=-1 unroll-full-threshold=1000}, "
                                     "affine-loop-unroll{unroll-factor=-1 unroll-num-reps=10})",
                                     pm))) {
    llvm_unreachable("pipeline is a hardcoded string and can always be parsed.");
  }

  // Lower leftover affine ops to scf.
  pm.addNestedPass<mlir::func::FuncOp>(mlir::createLowerAffinePass());

  // Dynamic to static allocation translation
  pm.addPass(mlir::createCanonicalizerPass());
  pm.addPass(qcc::createJaspCheckStaticQubitAllocation());
  pm.addPass(qcc::createConvertMemrefToStaticQubits());

  // Second cleanup
  pm.addNestedPass<mlir::func::FuncOp>(mlir::createCSEPass());

  // Whenever it makes sense (according to internal heuristics), promote a heap allocation
  // (`memref.alloc`) to a stack allocation (`memref.alloca`).
  pm.addNestedPass<mlir::func::FuncOp>(mlir::bufferization::createPromoteBuffersToStackPass());

  // Whenever it makes sense, promote stack-allocated variables (e.g. `memref<i64>`) to
  // plain register-values (e.g. `i64`).
  pm.addPass(mlir::createMem2Reg());

  // cleanup
  pm.addPass(mlir::createSCCPPass());
  pm.addNestedPass<mlir::func::FuncOp>(mlir::createCanonicalizerPass());
  pm.addNestedPass<mlir::func::FuncOp>(mlir::createCSEPass());
}
