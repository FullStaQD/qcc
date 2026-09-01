// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVec.h"
#include "qcc/Dialect/QVec/Transforms/Passes.h" // IWYU pragma: keep

#include "mlir/Dialect/QCO/IR/QCOOps.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <utility>

using namespace mlir;
using namespace qcc::qvec;

//===----------------------------------------------------------------------===//
// A uniform view of the qvec operations
//===----------------------------------------------------------------------===//

/// The number of qubits one slot of `op` carries, i.e. the op's current VF.
static int64_t getVectorLength(QubitSlotOpInterface op) { return op.getQubitResult(0).getType().getNumElements(); }

/// Identical bucket key for two ops expresses the fact that they can in principle be merged if no other op blocks and
/// qubit slots are disjoint. BucketKey = (operation name, secondary bucket key).
using BucketKey = std::pair<OperationName, uint32_t>;

/// Get the second component of the `BucketKey`.
///
/// Returning nullopt at runtime is considered a bug, hence the assert in the impl. We still emit a null-opt to avoid
/// correctness mistakes during production run. Returning a nullopt just means a possibly missed merge opportunity.
static std::optional<uint32_t> getSecondaryBucketKey(QubitSlotOpInterface op) {
  const std::optional<uint32_t> secondaryKey =
      TypeSwitch<Operation*, std::optional<uint32_t>>(op)
          .Case([](SingleOp singleOp) { return static_cast<uint32_t>(singleOp.getGateKind()); })
          .Case([](PairOp pairOp) { return static_cast<uint32_t>(pairOp.getGateKind()); })
          .Case([](MzOp) { return 0U; }) // A measurement has no gate kind its instances could differ in.
          .Default([](Operation*) { return std::nullopt; });

  assert(secondaryKey && "unhandled qvec operation, it stays unmerged");
  return secondaryKey;
}

//===----------------------------------------------------------------------===//
// Scheduling helpers
//===----------------------------------------------------------------------===//

/// Makes `value` available at `before`, hoisting whatever defines it if it is not already. Returns true iff succeeded.
/// IR might still be mutated if unsuccessful (but still correct).
///
/// TODO: we only hoist pure operations (in practice `vector.from_elements`, `vector.extract`, `qco.static`, etc). Not
/// because it is the right model but because it seems to be so strict a condition that it is correct in any case - but
/// needlessly restrictive. An example which does not hoist although it would make sense is: a1 = t(a0); a2 = t(a1); b1
/// = x(b0); b2 = t(b1). Here we could merge the first and last T-Gate, but the x (non-pure) would need to be hoisted
/// before a1 - which would be correct but we don't do it.
static bool makeAvailableBefore(Value value, Operation* before) {
  Operation* definingOp = value.getDefiningOp();
  if (definingOp == nullptr || definingOp->getBlock() != before->getBlock()) {
    return true; // A block argument, or defined in an enclosing region. Fine already.
  }
  if (definingOp->isBeforeInBlock(before)) {
    return true; // Fine already.
  }
  if (!isPure(definingOp)) {
    return false; // giving up.
  }

  // Recurse into operands.
  for (Value operand : definingOp->getOperands()) {
    if (!makeAvailableBefore(operand, before)) {
      return false;
    }
  }

  definingOp->moveBefore(before);

  return true;
}

//===----------------------------------------------------------------------===//
// Packing
//===----------------------------------------------------------------------===//

namespace {

/// The operations supposed to be merged into one, plus what the admission test needs.
struct Group {
  SmallVector<QubitSlotOpInterface> members;
  /// Total number of qubits per operand slot, i.e. the VF the merged operation would have.
  int64_t width = 0;
  /// The qubits the group acts on, i.e. the merged operations would have.
  DenseSet<Value> qubits; // FIXME: TypedValue of Qubit?

  /// Build the first (slot=0) or second (slot=1, if available) qubit vector operand for the merged operation by
  /// collecting each member's qubits in the same slots.
  Value buildMergedOperand(OpBuilder& builder, Location loc, unsigned slot) const {
    assert(slot == 0 || slot == 1 && "slot can only be 0 or 1");
    SmallVector<Value> elements;
    for (QubitSlotOpInterface member : this->members) {
      TypedValue<VectorType> operand = member.getQubitOperand(slot);
      for (int64_t index = 0; index < operand.getType().getNumElements(); ++index) {
        elements.push_back(vector::ExtractOp::create(builder, loc, operand, index));
      }
    }

    auto vectorType = VectorType::get({this->width}, elements.front().getType());
    return vector::FromElementsOp::create(builder, loc, vectorType, elements);
  }
};

} // namespace

/// Returns the list of static qubits this `qvec` op operates on. Or nullopt if any of them cannot be identified.
///
/// The static ops are found by tracing each qubit element through the IR.
static std::optional<SmallVector<qco::StaticOp>> getStaticQubits(QubitSlotOpInterface op) {
  SmallVector<qco::StaticOp> qubits;
  for (auto operand : op.getQubitOperands()) {
    for (int64_t index = 0; index < operand.getType().getNumElements(); ++index) {
      qco::StaticOp staticOp = getStaticOpAncestor(operand, index);
      if (!staticOp) {
        return std::nullopt; // FIXME: assert this does not happen?
      }
      qubits.push_back(staticOp);
    }
  }
  return qubits;
}

/// Extracts elements `[offset, offset + width)` out of `merged` as a vector of its own.
///
/// Use case: To enable the users of group members (which are now merged) to act on the right slice.
static Value buildMemberSlice(OpBuilder& builder, Location loc, Value merged, int64_t offset, int64_t width) {
  SmallVector<Value> elements;
  for (int64_t index = offset; index < offset + width; ++index) {
    elements.push_back(vector::ExtractOp::create(builder, loc, merged, index));
  }

  // FIXME: would it make sense to extract the whole slice directly (no multi extract + from_elements combo)?
  auto vectorType = VectorType::get({width}, elements.front().getType());
  return vector::FromElementsOp::create(builder, loc, vectorType, elements);
}

/// Replaces `group`'s members with one operation over all their qubits. The merged operation goes where the first
/// member was.
static void mergeGroup(const Group& group) {
  if (group.members.size() <= 1) {
    return; // trivial case
  }

  QubitSlotOpInterface firstOp = group.members.front();
  OpBuilder builder(firstOp); // important: sets insertion point right before firstOp.
  Location loc = firstOp->getLoc();

  SmallVector<Value, 2> operands;
  for (unsigned slot = 0, numSlots = firstOp.getNumQubitSlots(); slot < numSlots; ++slot) {
    operands.push_back(group.buildMergedOperand(builder, loc, slot));
  }

  Operation* merged =
      TypeSwitch<Operation*, Operation*>(firstOp)
          .Case([&](SingleOp singleOp) {
            return SingleOp::create(builder, loc, operands[0].getType(), singleOp.getGateKind(), operands[0]);
          })
          .Case([&](PairOp pairOp) {
            return PairOp::create(builder, loc, operands[0].getType(), operands[1].getType(), pairOp.getGateKind(),
                                  operands[0], operands[1]);
          })
          .Case([&](MzOp) {
            auto bitsType = VectorType::get({group.width}, builder.getI1Type());
            return MzOp::create(builder, loc, operands[0].getType(), bitsType, operands[0]);
          });

  // Replace uses of members by our newly created merged op.
  int64_t offset = 0;
  for (QubitSlotOpInterface member : group.members) {
    const int64_t width = getVectorLength(member);
    SmallVector<Value> replacements;
    for (Value result : merged->getResults()) {
      replacements.push_back(buildMemberSlice(builder, member->getLoc(), result, offset, width));
    }
    member->replaceAllUsesWith(replacements);
    offset += width;
  }

  for (QubitSlotOpInterface member : group.members) {
    member->erase();
  }
}

/// Merges one block's `qvec` operations, up to `limitVF` qubits per operation. This is the central method of the pass,
/// so let us explain how it works. For clarity we skip minor details, which are addressed by comments in the
/// implementation.
///
/// *Producers:* The *producers* of a `qvec` op are all the `qvec` ops immediately involved in creating its qubit
/// operands.
///
/// *Layering:* Every `qvec` op is assigned an integer layer: `layer(op) = 1 + max{layer(producer)}` over all producers
/// of `op`. An op without producers (e.g. the first `qvec` op in the block) gets layer `0`.
///
/// IMPORTANT: We cannot always determine all producers (incomplete producers), for example because unknown ops "block"
/// the way. Any pipeline this pass runs in is urged to avoid that scenario, as we optimize under the assumption of
/// complete producers. An underestimated layer propagates downstream: an op whose own producers are complete still gets
/// a wrong layer if any op upstream of it has incomplete ones.
///
/// If no `qvec` op has incomplete producers, it is easy to see that all `qvec` ops in the same layer operate on
/// disjoint qubits. Hence two gates of the same type can in principle always be merged. In general we cannot rely on
/// that, so we add extra checks for correctness.
///
/// *Bucketing:* Next we build a multi-map from `(layer, bucket key)` to `qvec` ops, with one entry per `qvec` op with
/// complete producers. The details of the bucket key do not matter, only that ops with an equal bucket key can in
/// principle be merged if their qubit operands are disjoint and nothing in the IR stands in the way (simplest case:
/// they are consecutive, no other op in between). Ops sharing a `(layer, bucket key)` form a bucket, and only ops
/// within one bucket are considered for merging.
///
/// *Sorting:* In the next step (grouping) we process the buckets in ascending order of layer. This makes sense because
/// merging within a layer typically unblocks merge opportunities in a follow-up layer (layers are in general
/// interleaved in the IR).
///
/// *Grouping:* Within each bucket we form groups of `qvec` operations (meant to be merged in the end). A group is a
/// list of `qvec` operations ordered as in the IR. Before a candidate is added to a group, the following tests have to
/// pass:
///
/// 1. The enlarged group still respects `limitVF` once merged.
/// 2. All qubits of the candidate can be traced back to static ops.
/// 3. All new qubits are disjoint from the ones the group already operates on (a safety net against incomplete
///    producers).
/// 4. The qubit operands of the candidate are already defined before the first member, or can be hoisted "easily"
///    (which is then done, and kept even if another operand fails this test). See `makeAvailableBefore` for details.
///
/// *Merging:* The members of a group are merged as soon as one of the tests fails (the candidate is then not added) or
/// the bucket is exhausted. If the bucket is not exhausted, the failing candidate itself opens the next group - unless
/// it can never be a member at all, i.e. it failed test 2, or fails test 1 on its own.
static void mergeOpsInBlock(Block& block, int64_t limitVF) {
  // Layering. layer(op) = 1 + max(layer(op_pred) for all predecessors op_pred of op).
  DenseMap<Operation*, unsigned> layers;
  llvm::MapVector<std::pair<unsigned, BucketKey>, SmallVector<QubitSlotOpInterface>> buckets;
  for (Operation& op : block) {
    auto slotOp = dyn_cast<QubitSlotOpInterface>(&op);
    if (!slotOp) {
      continue;
    }

    SmallPtrSet<Operation*, 4> producers;
    bool allProducersKnown = true;
    for (auto operand : slotOp.getQubitOperands()) {
      allProducersKnown &= collectQubitProducers(operand, producers);
    }

    unsigned layer = 0;
    for (Operation* producer : producers) {
      auto it = layers.find(producer);
      if (it != layers.end()) {
        layer = std::max(layer, it->second + 1);
      }
    }

    // An operation we cannot bucket still takes part in the layering, so that its consumers end up in a later layer.
    layers[slotOp] = layer;

    // If a producer is missing the layer might have a higher value than what we assigned. We do not bucket the op in
    // this case (meaning it does not participate in merging) to avoid mistakes.
    if (!allProducersKnown) {
      continue;
    }

    const std::optional<uint32_t> secondaryKey = getSecondaryBucketKey(slotOp);
    if (!secondaryKey) {
      continue;
    }
    buckets[{layer, BucketKey{op.getName(), *secondaryKey}}].push_back(slotOp);
  }

  // Sort keys by layer index (ascending).
  SmallVector<std::pair<unsigned, BucketKey>> keys = llvm::to_vector(llvm::make_first_range(buckets));
  llvm::stable_sort(keys, [](const auto& lhs, const auto& rhs) { return lhs.first < rhs.first; });

  auto close = [](Group& group) {
    mergeGroup(group);
    group = Group{};
  };

  for (const auto& key : keys) {
    Group group;
    for (QubitSlotOpInterface candidate : buckets[key]) {
      const int64_t width = getVectorLength(candidate);
      std::optional staticQubits = getStaticQubits(candidate);

      // A candidate whose qubits cannot be identified, or that exceeds the limit all by itself, never becomes a
      // member - not even the first one of a group.
      if (!staticQubits || width > limitVF) {
        close(group);
        continue;
      }

      // The group tests (or empty).
      const bool emptyOrFits =
          group.members.empty() ||
          (group.width + width <= limitVF &&
           llvm::none_of(*staticQubits, [&](Value qubit) { return group.qubits.contains(qubit); }) &&
           llvm::all_of(candidate.getQubitOperands(),
                        [&](Value operand) { return makeAvailableBefore(operand, group.members.front()); }));

      if (!emptyOrFits) {
        close(group); // The candidate opens the next group.
      }

      group.members.push_back(candidate);
      group.width += width;
      group.qubits.insert_range(*staticQubits);
    }
    close(group);
  }
}

namespace qcc {

#define GEN_PASS_DEF_QVECMERGE
#include "qcc/Dialect/QVec/Transforms/Passes.h.inc"

namespace {

struct QVecMerge final : impl::QVecMergeBase<QVecMerge> {
  using QVecMergeBase::QVecMergeBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();

    // A max-vf of 0 leaves VF (vectorization factor) unbounded; see the pass description.
    const int64_t limitVF = maxVF == 0 ? std::numeric_limits<int64_t>::max() : maxVF;

    SmallVector<Block*> blocks;
    moduleOp->walk([&](Block* block) { blocks.push_back(block); });
    for (Block* block : blocks) {
      mergeOpsInBlock(*block, limitVF);
    }

    // Merging takes a qubit vector apart element by element and immediately puts it back together again. This leads to
    // verbose IR which we canonicalize (and simplify) here.
    RewritePatternSet patterns(ctx);
    vector::FromElementsOp::getCanonicalizationPatterns(patterns, ctx);
    if (failed(applyPatternsGreedily(moduleOp, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
