// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Qcc/IR/Qcc.h"
#include "qcc/Dialect/Qcc/Transforms/Passes.h" // IWYU pragma: keep

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Bufferization/Transforms/OneShotAnalysis.h"
#include "mlir/Dialect/Bufferization/Transforms/OneShotModuleBufferize.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace qcc {

#define GEN_PASS_DEF_QCCONESHOTBUFFERIZE
#include "qcc/Dialect/Qcc/Transforms/Passes.h.inc"

/// Whether an operand, a result or a block argument of a region of `op` is an array of qubits.
static bool holdsQubitArray(Operation* op) {
  auto isArray = [](Value value) { return isQubitArray(value.getType()); };
  return llvm::any_of(op->getOperands(), isArray) || llvm::any_of(op->getResults(), isArray) ||
         llvm::any_of(op->getRegions(), [&](Region& region) {
           return llvm::any_of(region, [&](Block& block) { return llvm::any_of(block.getArguments(), isArray); });
         });
}

namespace {

struct QccOneShotBufferize final : impl::QccOneShotBufferizeBase<QccOneShotBufferize> {
  using QccOneShotBufferizeBase::QccOneShotBufferizeBase;

protected:
  void runOnOperation() override {
    ModuleOp module = getOperation();

    // The ops that hold arrays of qubits are skipped below. They must not be bufferizable ops with other tensors, and
    // nothing may bufferize the arrays they pass on.
    const WalkResult result = module.walk<WalkOrder::PreOrder>([&](Operation* op) {
      if (isa<AllocOp, DeallocOp>(op) || isa_and_present<tensor::TensorDialect>(op->getDialect()) ||
          !holdsQubitArray(op)) {
        return WalkResult::advance();
      }
      op->emitOpError() << "holds an array of qubits, but " << getArgument()
                        << " expects only 'qcc.alloc', 'qcc.dealloc' and 'tensor' ops to hold arrays of qubits";
      return WalkResult::interrupt();
    });
    if (result.wasInterrupted()) {
      return signalPassFailure();
    }

    // The other options keep their defaults, which are also those of `one-shot-bufferize`.
    bufferization::OneShotBufferizationOptions options;
    options.allowReturnAllocsFromLoops = allowReturnAllocsFromLoops;
    options.allowUnknownOps = allowUnknownOps;
    options.bufferizeFunctionBoundaries = bufferizeFunctionBoundaries;
    options.opFilter.denyOperation(holdsQubitArray);

    bufferization::BufferizationState state;
    const LogicalResult bufferized = bufferizeFunctionBoundaries
                                         ? bufferization::runOneShotModuleBufferize(module, options, state)
                                         : bufferization::runOneShotBufferize(module, options, state);
    if (failed(bufferized)) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
