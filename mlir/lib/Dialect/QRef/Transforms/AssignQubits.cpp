// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// `qref-assign-qubits` first checks that no function with qubits is called, since each function is a program on its
// own. Then, for each function, it walks the function and decides on the static qubits of every allocation, so that a
// failure leaves the function untouched, and then rewrites the allocations and erases the deallocs.
//
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QRef/IR/QRef.h"
#include "qcc/Dialect/QRef/Transforms/Passes.h" // IWYU pragma: keep
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/LoopLikeInterface.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cassert>
#include <cstddef>
#include <cstdint>
#include <optional>

namespace qcc {

#define GEN_PASS_DEF_QREFASSIGNQUBITS
#include "qcc/Dialect/QRef/Transforms/Passes.h.inc"

using namespace mlir;

namespace {

/// The static qubit for one qubit of an allocation.
struct AssignedQubit {
  int64_t index;
  /// Whether the qubit may be in a state other than |0⟩, so that it must be reset: a dealloc freed it before, or the
  /// allocation may run repeatedly.
  bool needsReset;
};

/// The qubits that one dealloc frees, in array order.
struct FreedQubits {
  DeallocOp dealloc;
  SmallVector<int64_t> indices;
  /// How many of `indices`, from the front, are reused already.
  size_t numReused = 0;
};

class QubitAssigner {
public:
  QubitAssigner(func::FuncOp func, StringRef passName) : func(func), passName(passName), dominance(func) {}

  LogicalResult run() {
    func.walk([&](StaticRefOp staticRef) { reserved.insert_range(staticRef.getIndices()); });

    const WalkResult result = func.walk([&](Operation* op) {
      LogicalResult assigned = success();
      if (auto alloc = dyn_cast<AllocOp>(op)) {
        assigned = assign(alloc);
      } else if (auto dealloc = dyn_cast<DeallocOp>(op)) {
        assigned = recordFreed(dealloc);
      }
      return succeeded(assigned) ? WalkResult::advance() : WalkResult::interrupt();
    });
    if (result.wasInterrupted()) {
      return failure();
    }

    rewrite();
    return success();
  }

private:
  //===--------------------------------------------------------------------===//
  // Analysis
  //===--------------------------------------------------------------------===//

  /// Decides on the static qubits of `alloc`. Fails if its size is not a non-negative constant, if it may run in
  /// parallel with itself, or if it may run repeatedly but its block does not free it.
  LogicalResult assign(AllocOp alloc) {
    std::optional<int64_t> size = 1;
    if (auto arrayType = dyn_cast<RankedTensorType>(alloc.getType())) {
      size = arrayType.hasStaticShape() ? arrayType.getDimSize(0) : getConstantIntValue(alloc.getDynamicSize());
    }
    if (!size) {
      return alloc.emitOpError() << "allocates a dynamic number of qubits, but " << passName
                                 << " expects a constant number";
    }
    if (*size < 0) {
      return alloc.emitOpError() << "allocates a negative number of qubits: " << *size;
    }
    // A run of a repeated allocation gets the same qubits as the previous run, so that run must have freed them.
    const FailureOr<bool> repeated = mayRunRepeatedly(alloc);
    if (failed(repeated)) {
      return failure();
    }
    if (*repeated && !isFreedInItsBlock(alloc)) {
      return alloc.emitOpError() << "may run repeatedly, but " << passName
                                 << " expects such an allocation to be freed by a 'qcc.dealloc' in its block";
    }

    SmallVector<AssignedQubit>& qubits = assignments[alloc];
    for (int64_t i = 0; i < *size; ++i) {
      if (const std::optional<int64_t> index = takeFreed(alloc)) {
        qubits.push_back({.index = *index, .needsReset = true});
        continue;
      }
      while (reserved.contains(nextIndex)) {
        ++nextIndex;
      }
      qubits.push_back({.index = nextIndex++, .needsReset = *repeated});
    }
    return success();
  }

  /// Whether `alloc` may run more than once in one run of the function, one run after the other. Fails if it may run in
  /// parallel with itself: we *could* hand out distinct qubits for each iteration but this is impractical for hardware.
  ///
  /// Only a cycle of branches, `scf.for` and `scf.while` run their blocks repeatedly but one run after the other. Any
  /// other region must be known to run at most once: a region of a `RegionBranchOpInterface` op that is not a loop and
  /// does not repeat the region. The loop check is needed for `scf.forall`: it runs its body once per iteration, but in
  /// parallel, so the interface sees no cycle.
  FailureOr<bool> mayRunRepeatedly(AllocOp alloc) const {
    bool repeated = false;
    Operation* op = alloc;
    while (true) {
      Block* block = op->getBlock();
      if (block->isReachable(block)) {
        repeated = true;
      }
      op = op->getParentOp();
      if (op == func) {
        return repeated;
      }
      if (isa<scf::ForOp, scf::WhileOp>(op)) {
        repeated = true;
        continue;
      }
      auto branch = dyn_cast<RegionBranchOpInterface>(op);
      if (!branch || isa<LoopLikeOpInterface>(op) || branch.isRepetitiveRegion(block->getParent()->getRegionNumber())) {
        return alloc.emitOpError() << "may run in parallel with itself in '" << op->getName() << "', which " << passName
                                   << " does not support";
      }
    }
  }

  /// Whether a dealloc in the block of `alloc` frees it, possibly through `tensor.cast`.
  static bool isFreedInItsBlock(AllocOp alloc) {
    SmallVector<Value> worklist = {alloc.getResult()};
    while (!worklist.empty()) {
      const Value qubits = worklist.pop_back_val();
      for (Operation* user : qubits.getUsers()) {
        if (isa<DeallocOp>(user) && user->getBlock() == alloc->getBlock()) {
          return true;
        }
        if (auto cast = dyn_cast<tensor::CastOp>(user)) {
          worklist.push_back(cast.getResult());
        }
      }
    }
    return false;
  }

  /// Takes a qubit that a dealloc dominating `alloc` freed, from the most recent such dealloc.
  std::optional<int64_t> takeFreed(AllocOp alloc) {
    for (FreedQubits& freedQubits : llvm::reverse(freed)) {
      if (freedQubits.numReused < freedQubits.indices.size() &&
          dominance.properlyDominates(freedQubits.dealloc, alloc)) {
        return freedQubits.indices[freedQubits.numReused++];
      }
    }
    return std::nullopt;
  }

  /// Records the qubits that `dealloc` frees. Fails if they are not the result of an allocation.
  LogicalResult recordFreed(DeallocOp dealloc) {
    Value qubits = dealloc.getQubits();
    while (auto cast = qubits.getDefiningOp<tensor::CastOp>()) {
      qubits = cast.getSource();
    }
    auto alloc = qubits.getDefiningOp<AllocOp>();
    if (!alloc) {
      return dealloc.emitOpError() << "frees qubits other than the result of a 'qcc.alloc', which " << passName
                                   << " does not support";
    }

    // The allocation dominates the dealloc, so the walk assigned it before.
    auto* it = assignments.find(alloc);
    assert(it != assignments.end() && "the allocation is visited before its dealloc");
    FreedQubits& freedQubits = freed.emplace_back();
    freedQubits.dealloc = dealloc;
    for (const AssignedQubit& qubit : it->second) {
      freedQubits.indices.push_back(qubit.index);
    }
    return success();
  }

  //===--------------------------------------------------------------------===//
  // Rewrite
  //===--------------------------------------------------------------------===//

  /// Replaces each allocation by its static qubits and erases the deallocs.
  void rewrite() {
    for (FreedQubits& freedQubits : freed) {
      freedQubits.dealloc.erase();
    }

    const auto qubitRefType = QubitRefType::get(func.getContext());
    for (auto& [alloc, qubits] : assignments) {
      OpBuilder builder(alloc);
      const Location loc = alloc.getLoc();
      SmallVector<Value> refs;
      for (const AssignedQubit& qubit : qubits) {
        Value ref = StaticRefOp::create(builder, loc, ArrayRef(qubit.index)).getQubits().front();
        if (qubit.needsReset) {
          qref::ResetOp::create(builder, loc, Basis::Z, ref);
        }
        refs.push_back(ref);
      }

      Value replacement;
      if (!isQubitArray(alloc.getType())) {
        replacement = refs.front();
      } else {
        auto arrayType = RankedTensorType::get({static_cast<int64_t>(refs.size())}, qubitRefType);
        replacement = tensor::FromElementsOp::create(builder, loc, arrayType, refs);
        if (arrayType != alloc.getType()) {
          replacement = tensor::CastOp::create(builder, loc, alloc.getType(), replacement);
        }
      }
      alloc.replaceAllUsesWith(replacement);
      alloc.erase();
    }
  }

  func::FuncOp func;
  StringRef passName;
  DominanceInfo dominance;

  /// The indices that a `qcc.static_ref` names. They are never handed out.
  llvm::DenseSet<int64_t> reserved;
  /// The next index to hand out, unless it is reserved.
  int64_t nextIndex = 0;
  /// The static qubits of each allocation, in walk order.
  llvm::MapVector<AllocOp, SmallVector<AssignedQubit>> assignments;
  /// The qubits that each dealloc frees, in walk order.
  SmallVector<FreedQubits> freed;
};

} // namespace

/// Fails if anything calls or refers to a function that allocates or names qubits: the qubits of each function are
/// assigned as if it were a program on its own.
static LogicalResult checkQubitFunctionsAreNotCalled(ModuleOp module, StringRef passName) {
  SymbolTableCollection symbolTables;
  const SymbolUserMap users(symbolTables, module);
  bool called = false;
  for (auto func : module.getOps<func::FuncOp>()) {
    const WalkResult hasQubits = func.walk(
        [](Operation* op) { return isa<AllocOp, StaticRefOp>(op) ? WalkResult::interrupt() : WalkResult::advance(); });
    if (!hasQubits.wasInterrupted()) {
      continue;
    }
    for (Operation* user : users.getUsers(func)) {
      user->emitOpError() << (isa<CallOpInterface>(user) ? "calls @" : "refers to @") << func.getSymName()
                          << ", which allocates or names qubits, but " << passName
                          << " expects such a function never to be called";
      called = true;
    }
  }
  return failure(called);
}

namespace {

struct QRefAssignQubits final : impl::QRefAssignQubitsBase<QRefAssignQubits> {
  using QRefAssignQubitsBase::QRefAssignQubitsBase;

protected:
  void runOnOperation() override {
    ModuleOp module = getOperation();
    if (failed(checkQubitFunctionsAreNotCalled(module, getArgument()))) {
      return signalPassFailure();
    }
    // A failure in one function leaves the others to be assigned, so that all their errors are reported.
    bool assigned = true;
    for (auto func : module.getOps<func::FuncOp>()) {
      if (failed(QubitAssigner(func, getArgument()).run())) {
        assigned = false;
      }
    }
    if (!assigned) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
