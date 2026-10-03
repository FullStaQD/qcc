// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Aux_/IR/Aux_.h"
#include "qcc/Dialect/Magic/IR/Magic.h"
#include "qcc/Dialect/Magic/Transforms/Passes.h" // IWYU pragma: keep

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <utility>

using namespace mlir;

namespace qcc::magic {

#define GEN_PASS_DEF_MAGICMEASUREANDRECORDGARBAGE
#include "qcc/Dialect/Magic/Transforms/Passes.h.inc"

/// Measures every non-empty chain of `block` that no op consumes. The measurements come right after the last magic
/// op, where every chain value is available.
static void measureUnmeasuredChains(Block& block) {
  SmallVector<TypedValue<IonChainType>> unmeasured;
  Operation* lastMagicOp = nullptr;
  for (Operation& op : block) {
    if (!isa_and_present<MagicDialect>(op.getDialect())) {
      continue;
    }
    lastMagicOp = &op;
    for (Value result : op.getResults()) {
      auto chain = dyn_cast<TypedValue<IonChainType>>(result);
      if (chain && chain.use_empty() && chain.getType().getNumIons() > 0) {
        unmeasured.push_back(chain);
      }
    }
  }

  if (unmeasured.empty()) {
    return;
  }

  OpBuilder builder(lastMagicOp->getContext());
  builder.setInsertionPointAfter(lastMagicOp);
  for (const TypedValue<IonChainType> chain : unmeasured) {
    const SmallVector<Type> bits(chain.getType().getNumIons(), builder.getI1Type());
    MZDOp::create(builder, chain.getLoc(), bits, chain);
  }
}

/// Records every measurement result of `block` that has no use, ordered by ion id. The records come at the end of
/// the block, after all records of the program, and are marked as garbage.
static void recordUnrecordedResults(Block& block) {
  SmallVector<std::pair<int64_t, Value>> unrecorded;
  for (Operation& op : block) {
    auto mzd = dyn_cast<MZDOp>(op);
    if (!mzd) {
      continue;
    }
    for (auto [ion, bit] : llvm::zip_equal(mzd.getChain().getType().getIons(), mzd.getBits())) {
      if (bit.use_empty()) {
        unrecorded.emplace_back(ion, bit);
      }
    }
  }
  llvm::sort(unrecorded, llvm::less_first());

  OpBuilder builder(block.getTerminator());
  const MagicDialect::GarbageResultAttrHelper garbageResult(builder.getContext());
  for (auto [ion, bit] : unrecorded) {
    auto record = aux::RecordIntOp::create(builder, bit.getLoc(), bit);
    garbageResult.setAttr(record, builder.getUnitAttr());
  }
}

namespace {

struct MagicMeasureAndRecordGarbage final : impl::MagicMeasureAndRecordGarbageBase<MagicMeasureAndRecordGarbage> {
  using MagicMeasureAndRecordGarbageBase::MagicMeasureAndRecordGarbageBase;

protected:
  void runOnOperation() override {
    func::FuncOp func = getOperation();
    if (func.isExternal()) {
      return;
    }
    measureUnmeasuredChains(func.front());
    recordUnrecordedResults(func.front());
  }
};

} // namespace
} // namespace qcc::magic
