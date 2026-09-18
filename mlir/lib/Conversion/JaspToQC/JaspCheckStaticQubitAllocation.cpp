// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/JaspToQC/JaspToQC.h"

#include "mqt/Dialect/QC/IR/QCDialect.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Support/LLVM.h"

namespace qcc {

#define GEN_PASS_DEF_JASPCHECKSTATICQUBITALLOCATION
#include "qcc/Conversion/JaspToQC/JaspToQC.h.inc"

using namespace mlir;
using namespace mlir::qc;

namespace {

struct JaspCheckStaticQubitAllocation final
    : public impl::JaspCheckStaticQubitAllocationBase<JaspCheckStaticQubitAllocation> {
  using JaspCheckStaticQubitAllocationBase<JaspCheckStaticQubitAllocation>::JaspCheckStaticQubitAllocationBase;

protected:
  void runOnOperation() override {
    Operation* op = getOperation();
    WalkResult result = op->walk([&](memref::AllocOp allocOp) {
      auto memrefType = dyn_cast<MemRefType>(allocOp.getType());

      if (!memrefType || !isa<qc::QubitType>(memrefType.getElementType())) {
        return WalkResult::advance();
      }

      if (memrefType.isDynamicDim(0)) {
        allocOp.emitError("qubit array allocation size must be a compile-time constant; "
                          "dynamic qubit array sizes are not supported");
        return WalkResult::interrupt();
      }

      auto size = memrefType.getDimSize(0);
      if (size <= 0) {
        allocOp.emitError("qubit array size must be positive, got ") << size;
        return WalkResult::interrupt();
      }

      return WalkResult::advance();
    });

    if (result.wasInterrupted()) {
      return signalPassFailure();
    }
  }
};
} // namespace
} // namespace qcc
