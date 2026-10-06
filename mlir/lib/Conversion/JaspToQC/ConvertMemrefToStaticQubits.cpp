// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/JaspToQC/JaspToQC.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/QC/IR/QCDialect.h"
#include "mlir/Dialect/QC/IR/QCOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Types.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

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

    // The qubits each dealloc frees. An alloc reuses them only if that dealloc dominates it.
    DominanceInfo dominance(op);
    SmallVector<std::pair<memref::DeallocOp, SmallVector<Value>>> freed;
    auto takeFreedQubit = [&](memref::AllocOp allocOp) -> Value {
      for (auto& [deallocOp, qubits] : freed) {
        if (!qubits.empty() && dominance.properlyDominates(deallocOp, allocOp)) {
          return qubits.pop_back_val();
        }
      }
      return {};
    };

    // --- Step 1: Lower Allocations to Static Hardware Qubits ---
    // We treat every 'alloc' as a request for N physical qubits.
    // We generate these qubits immediately and store them in our map.
    WalkResult result = op->walk([&](Operation* memrefOp) {
      if (auto deallocOp = dyn_cast<memref::DeallocOp>(memrefOp)) {
        Value memref = deallocOp.getMemref();
        while (auto castOp = memref.getDefiningOp<memref::CastOp>()) {
          memref = castOp.getSource();
        }
        auto freedAlloc = memref.getDefiningOp<memref::AllocOp>();
        if (freedAlloc && isQubitMemref(freedAlloc.getType())) {
          SmallVector<Value> qubits;
          for (int64_t i = freedAlloc.getType().getDimSize(0) - 1; i >= 0; --i) {
            qubits.push_back(qubitMap.lookup({freedAlloc.getResult(), i}));
          }
          freed.emplace_back(deallocOp, std::move(qubits));
        }
        return WalkResult::advance();
      }

      auto allocOp = dyn_cast<memref::AllocOp>(memrefOp);
      if (!allocOp || !isQubitMemref(allocOp.getType())) {
        return WalkResult::advance();
      }

      auto memrefType = cast<MemRefType>(allocOp.getType());
      if (memrefType.isDynamicDim(0)) {
        allocOp->emitError("found dynamic qubit allocation; expected static size from previous pass");
        return WalkResult::interrupt();
      }

      int64_t size = memrefType.getDimSize(0);
      builder.setInsertionPoint(allocOp);

      // Reuse a freed qubit after resetting it, or create a new 'static' op for the slot.
      for (int64_t i = 0; i < size; i++) {
        Value qubit = takeFreedQubit(allocOp);
        if (qubit) {
          qc::ResetOp::create(builder, allocOp->getLoc(), qubit);
        } else {
          qubit = qc::StaticOp::create(builder, allocOp->getLoc(), nextGlobalQubitIdx++).getResult();
        }
        qubitMap[{allocOp.getResult(), i}] = qubit;
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
    // Erase deallocs immediately because nothing uses them. Erase casts and allocs afterwards in reverse order, so
    // every op is erased after its users.
    SmallVector<Operation*> toErase;
    op->walk([&](Operation* memrefOp) {
      if (auto deallocOp = dyn_cast<memref::DeallocOp>(memrefOp)) {
        if (isQubitMemref(deallocOp.getMemref().getType())) {
          deallocOp->erase();
        }
      } else if (auto allocOp = dyn_cast<memref::AllocOp>(memrefOp)) {
        if (isQubitMemref(allocOp.getType())) {
          toErase.push_back(allocOp);
        }
      } else if (auto castOp = dyn_cast<memref::CastOp>(memrefOp)) {
        if (isQubitMemref(castOp.getType())) {
          toErase.push_back(castOp);
        }
      }
    });

    for (Operation* memrefOp : llvm::reverse(toErase)) {
      memrefOp->erase();
    }
  }
};
} // namespace
} // namespace qcc
