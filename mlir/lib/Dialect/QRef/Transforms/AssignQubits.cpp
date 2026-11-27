// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// `qref-assign-qubits` first walks each function and decides on the static qubits of every allocation, so that a
// failure leaves the IR untouched. Then it rewrites the allocations and erases the deallocs.
//
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QRef/IR/QRef.h"
#include "qcc/Dialect/QRef/Transforms/Passes.h" // IWYU pragma: keep
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/Visitors.h"
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
  /// Whether a dealloc freed the qubit before, so that it must be reset.
  bool reused;
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

  /// Decides on the static qubits of `alloc`. Fails if its size is not a non-negative constant.
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

    SmallVector<AssignedQubit>& qubits = assignments[alloc];
    for (int64_t i = 0; i < *size; ++i) {
      if (const std::optional<int64_t> index = takeFreed(alloc)) {
        qubits.push_back({.index = *index, .reused = true});
        continue;
      }
      while (reserved.contains(nextIndex)) {
        ++nextIndex;
      }
      qubits.push_back({.index = nextIndex++, .reused = false});
    }
    return success();
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
        if (qubit.reused) {
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

struct QRefAssignQubits final : impl::QRefAssignQubitsBase<QRefAssignQubits> {
  using QRefAssignQubitsBase::QRefAssignQubitsBase;

protected:
  void runOnOperation() override {
    if (failed(QubitAssigner(getOperation(), getArgument()).run())) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
