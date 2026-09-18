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
#include "mqt/Dialect/QC/IR/QCOps.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Types.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseMap.h"

#include <utility>

namespace qcc {

#define GEN_PASS_DEF_CONVERTMEMREFTOSTATICQUBITS
#include "qcc/Conversion/JaspToQC/JaspToQC.h.inc"

using namespace mlir;
using namespace mlir::qc;

namespace {

struct ConvertMemrefToStaticQubits final : public impl::ConvertMemrefToStaticQubitsBase<ConvertMemrefToStaticQubits> {
  using ConvertMemrefToStaticQubitsBase<ConvertMemrefToStaticQubits>::ConvertMemrefToStaticQubitsBase;

private:
  /// Identifies if a type is a MemRef containing Qubits.
  static bool isQubitMemref(Type type) {
    auto mType = dyn_cast<MemRefType>(type);
    return mType && isa<qc::QubitType>(mType.getElementType());
  }

protected:
  void runOnOperation() override {
    Operation* op = getOperation();
    OpBuilder builder(op->getContext());

    // Tracks the mapping from a (MemRef, Index) pair to a specific physical qubit Value.
    // This essentially "flattens" the memory model into a lookup table.
    DenseMap<std::pair<Value, int64_t>, Value> qubitMap;

    // A global counter to ensure every physical qubit in the circuit gets a unique hardware ID.
    int64_t nextGlobalQubitIdx = 0;

    // --- Step 1: Lower Allocations to Static Hardware Qubits ---
    // We treat every 'alloc' as a request for N physical qubits.
    // We generate these qubits immediately and store them in our map.
    WalkResult result = op->walk([&](memref::AllocOp allocOp) {
      if (!isQubitMemref(allocOp.getType())) {
        return WalkResult::advance();
      }

      auto memrefType = cast<MemRefType>(allocOp.getType());
      if (memrefType.isDynamicDim(0)) {
        allocOp->emitError("found dynamic qubit allocation; expected static size from previous pass");
        return WalkResult::interrupt();
      }

      int64_t size = memrefType.getDimSize(0);
      builder.setInsertionPoint(allocOp);

      // Create a unique 'static' op for every slot in the memref.
      for (int64_t i = 0; i < size; i++) {
        auto staticQubit = qc::StaticOp::create(builder, allocOp->getLoc(), nextGlobalQubitIdx++);
        qubitMap[{allocOp.getResult(), i}] = staticQubit.getResult();
      }

      return WalkResult::advance();
    });

    if (result.wasInterrupted()) {
      signalPassFailure();
    }

    // --- Step 2: Resolve Loads to Static Values ---
    // We replace any 'load' operation with a direct reference to the physical qubit
    // created in Step 1. This effectively eliminates the need for the memref.
    WalkResult secondResult = op->walk([&](memref::LoadOp loadOp) {
      if (!isa<qc::QubitType>(loadOp.getType())) {
        return WalkResult::advance();
      }

      Value baseMemref = loadOp.getMemRef();
      Value indexVal = loadOp.getIndices()[0];

      // Qubit indexing must be constant because quantum hardware
      // cannot "dynamically" route wires at runtime.
      auto constantIdx = getConstantIntValue(indexVal);
      if (!constantIdx) {
        loadOp->emitError("qubit index must be a constant; unroll loops before this pass");
        return WalkResult::interrupt();
      }

      int64_t idx = *constantIdx;
      auto memrefType = cast<MemRefType>(baseMemref.getType());

      if (idx < 0 || idx >= memrefType.getDimSize(0)) {
        loadOp->emitError("qubit index out of bounds");
        return WalkResult::interrupt();
      }

      // Retrieve the pre-allocated physical qubit from our map.
      auto it = qubitMap.find({baseMemref, idx});
      if (it == qubitMap.end()) {
        loadOp->emitError("internal error: static qubit not found for this allocation");
        return WalkResult::interrupt();
      }

      // Replace all uses of the 'loaded' qubit with the 'static' hardware qubit. It deletes the loadOp as well.
      loadOp.getResult().replaceAllUsesWith(it->second);
      loadOp.erase();

      return WalkResult::advance();
    });

    if (secondResult.wasInterrupted()) {
      return signalPassFailure();
    }

    // --- Step 3: Deletes Dangling Memref Usages ---
    // Applies a third walk and removes all the memref instances that deal with qubit type.
    WalkResult thirdResult = op->walk([&](Operation* memrefOp) {
      if (auto allocOp = dyn_cast<memref::AllocOp>(memrefOp)) {
        if (isQubitMemref(allocOp.getType())) {
          allocOp->erase();
          return WalkResult::advance();
        }
      } else if (auto deallocOp = dyn_cast<memref::DeallocOp>(memrefOp)) {
        auto memrefType = dyn_cast<MemRefType>(deallocOp.getMemref().getType());
        if (memrefType && isQubitMemref(memrefType)) {
          deallocOp->erase();
          return WalkResult::advance();
        }
      } else if (auto castOp = dyn_cast<memref::CastOp>(memrefOp)) {
        auto memrefType = dyn_cast<MemRefType>(castOp.getType());
        if (memrefType && isQubitMemref(memrefType)) {
          castOp->erase();
          return WalkResult::advance();
        }
      }
      return WalkResult::advance();
    });

    if (thirdResult.wasInterrupted()) {
      signalPassFailure();
    }
  }
};
} // namespace
} // namespace qcc
