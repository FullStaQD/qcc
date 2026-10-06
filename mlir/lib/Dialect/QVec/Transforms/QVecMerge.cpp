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
#include "mlir/Transforms/RegionUtils.h"

#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <utility>

using namespace mlir;
using namespace qcc::qvec;

/// The number of qubits one lane of `op` carries, i.e. the op's current VF.
static int64_t getVectorLength(QubitLaneOpInterface op) { return op.getQubitResult(0).getType().getNumElements(); }

/// Identical bucket key for two ops expresses the fact that they can in principle be merged if no other op blocks and
/// qubit lanes are disjoint. BucketKey = (operation name, secondary bucket key).
using BucketKey = std::pair<OperationName, uint32_t>;

/// Get the second component of the `BucketKey`, or nullopt for an operation this pass never merges.
///
/// TODO(#141): Parametrised `single` / `pair` are left alone for now, because merging them means concatenating
/// their angle vectors (trivial for constants, a `vector.shuffle` / `vector.from_elements` for SSA vectors). Disjoint
/// `global zz` blocks could merge by direct sum of their (constant) matrices. Both belong to the merge rewrite.
static std::optional<uint32_t> getSecondaryBucketKey(QubitLaneOpInterface op) {
  return TypeSwitch<Operation*, std::optional<uint32_t>>(op)
      .Case([](SingleOp singleOp) -> std::optional<uint32_t> {
        if (!singleOp.getParams().empty()) {
          return std::nullopt;
        }
        return static_cast<uint32_t>(singleOp.getGateKind());
      })
      .Case([](PairOp pairOp) -> std::optional<uint32_t> {
        if (!pairOp.getParams().empty()) {
          return std::nullopt;
        }
        return static_cast<uint32_t>(pairOp.getGateKind());
      })
      .Case([](GlobalOp) -> std::optional<uint32_t> { return std::nullopt; })
      .Case([](MZOp) -> std::optional<uint32_t> { return 0U; }) // No gate kind its instances could differ in.
      .Default([](Operation*) -> std::optional<uint32_t> {
        assert(false && "unhandled qvec operation, it stays unmerged");
        return std::nullopt;
      });
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

/// The operations supposed to be merged into one, plus what the admission conditions need.
struct Group {
  SmallVector<QubitLaneOpInterface> members;
  /// Total number of qubits per operand lane, i.e. the VF the merged operation would have.
  int64_t width = 0;
  /// The qubits the group acts on, i.e. the merged operations would have.
  DenseSet<qco::StaticOp> qubits;

  /// Build the first (lane=0) or second (lane=1, if available) qubit vector operand for the merged operation by
  /// collecting each member's qubits in the same lanes.
  Value buildMergedOperand(OpBuilder& builder, Location loc, unsigned lane) const {
    assert((lane == 0 || lane == 1) && "lane can only be 0 or 1");
    SmallVector<Value> elements;
    for (QubitLaneOpInterface member : this->members) {
      TypedValue<VectorType> operand = member.getQubitOperand(lane);
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
static std::optional<SmallVector<qco::StaticOp>> getStaticQubits(QubitLaneOpInterface op) {
  SmallVector<qco::StaticOp> qubits;
  for (auto operand : op.getQubitOperands()) {
    for (int64_t index = 0; index < operand.getType().getNumElements(); ++index) {
      qco::StaticOp staticOp = getStaticOpAncestor(operand, index);
      if (!staticOp) {
        // Ideally we would like to never return nullopt, but this cannot be guaranteed if the pass is ran in an
        // arbitrary context.
        return std::nullopt;
      }
      qubits.push_back(staticOp);
    }
  }
  return qubits;
}

/// Replaces `group`'s members with one operation over all their qubits. The merged operation goes where the first
/// member was.
static void mergeGroup(const Group& group) {
  if (group.members.size() <= 1) {
    return; // trivial case
  }

  QubitLaneOpInterface firstOp = group.members.front();
  OpBuilder builder(firstOp); // important: sets insertion point right before firstOp.
  Location loc = firstOp->getLoc();

  SmallVector<Value, 2> operands;
  for (unsigned lane = 0, numLanes = firstOp.getNumQubitLanes(); lane < numLanes; ++lane) {
    operands.push_back(group.buildMergedOperand(builder, loc, lane));
  }

  Operation* merged =
      TypeSwitch<Operation*, Operation*>(firstOp)
          .Case([&](SingleOp singleOp) {
            return SingleOp::create(builder, loc, singleOp.getGateKind(), operands[0]); // parameter-free, see bucketing
          })
          .Case([&](PairOp pairOp) {
            return PairOp::create(builder, loc, pairOp.getGateKind(), operands[0], operands[1]);
          })
          .Case([&](MZOp) {
            auto bitsType = VectorType::get({group.width}, builder.getI1Type());
            return MZOp::create(builder, loc, operands[0].getType(), bitsType, operands[0]);
          });

  // Replace uses of members by our newly created merged op.
  int64_t offset = 0;
  for (QubitLaneOpInterface member : group.members) {
    const int64_t width = getVectorLength(member);
    SmallVector<Value> replacements;
    for (Value result : merged->getResults()) {
      replacements.push_back(vector::ExtractStridedSliceOp::create(
          builder, member->getLoc(), /*source=*/result, /*offsets=*/ArrayRef<int64_t>{offset},
          /*sizes=*/ArrayRef<int64_t>{width}, /*strides=*/ArrayRef<int64_t>{1}));
    }
    member->replaceAllUsesWith(replacements);
    offset += width;
  }

  for (QubitLaneOpInterface member : group.members) {
    member->erase();
  }
}

/// Merges one block's `qvec` operations, up to `limitVF` qubits per operation. This is the central method of the pass,
/// so let us explain how it works. For clarity we skip minor details, which are addressed by comments in the
/// implementation.
///
/// *Layering:* Every `qvec` op and every op with regions (e.g. `scf.if`) is assigned an integer layer: one more than
/// the highest layer it depends on through its operands, including values used inside its regions. Other ops only pass
/// on the highest layer of their operands. An op depending on no layered op (e.g. the first `qvec` op in the block)
/// gets layer `0`. Classical operands count as well, e.g. the measurement result an `scf.if` condition is computed
/// from.
///
/// Ops in the same layer never depend on each other through SSA values, which makes them merge candidates. Whether a
/// merge is legal is decided by the conditions under *Grouping*, all of which are required.
///
/// *Bucketing:* Next we build a multi-map from `(layer, bucket key)` to `qvec` ops, with one entry per `qvec` op. The
/// details of the bucket key do not matter, only that ops with an equal bucket key can in principle be merged if their
/// qubit operands are disjoint and nothing in the IR stands in the way (simplest case: they are consecutive, no other
/// op in between). Ops sharing a `(layer, bucket key)` form a bucket, and only ops within one bucket are considered for
/// merging.
///
/// *Sorting:* In the next step (grouping) we process the buckets in ascending order of layer. This makes sense because
/// merging within a layer typically unblocks merge opportunities in a follow-up layer (layers are in general
/// interleaved in the IR).
///
/// *Grouping:* Within each bucket we form groups of `qvec` operations (meant to be merged in the end). A group is a
/// list of `qvec` operations ordered as in the IR. Before a candidate is added to a group, the following conditions
/// have to hold:
///
/// 1. The enlarged group still respects `limitVF` once merged.
/// 2. All qubits of the candidate can be traced back to static ops, which condition 3 compares.
/// 3. All new qubits are disjoint from the ones the group already operates on. This is not guaranteed by layering, but
/// promised by affine semantics.
///    The check is performed as a rigidity measure against non-affine context
/// 4. The qubit operands of the candidate are already defined before the first member, or can be hoisted "easily"
///    (which is then done, and kept even if another operand violates this condition). See `makeAvailableBefore` for
///    details. The merged op takes the first member's place, and layers say nothing about where operands are defined.
///
/// *Merging:* The members of a group are merged as soon as one of the conditions does not hold (the candidate is then
/// not added) or the bucket is exhausted. If the bucket is not exhausted, the failing candidate itself opens the next
/// group - unless it can never be a member at all, i.e. it violates condition 2, or condition 1 on its own.
static void mergeOpsInBlock(Block& block, int64_t limitVF) {
  // The lowest layer a user of the op's results can get. Values defined outside the block map to 0.
  DenseMap<Operation*, unsigned> userLayers;
  auto userLayerOf = [&](Value value) { return userLayers.lookup(value.getDefiningOp()); };

  llvm::MapVector<std::pair<unsigned, BucketKey>, SmallVector<QubitLaneOpInterface>> buckets;
  for (Operation& op : block) {
    unsigned layer = 0;
    for (Value operand : op.getOperands()) {
      layer = std::max(layer, userLayerOf(operand));
    }
    SetVector<Value> captures;
    getUsedValuesDefinedAbove(op.getRegions(), captures);
    for (Value capture : captures) {
      layer = std::max(layer, userLayerOf(capture));
    }

    auto laneOp = dyn_cast<QubitLaneOpInterface>(&op);
    userLayers[&op] = laneOp || op.getNumRegions() != 0 ? layer + 1 : layer;
    if (!laneOp) {
      continue;
    }

    const std::optional<uint32_t> secondaryKey = getSecondaryBucketKey(laneOp);
    if (!secondaryKey) {
      continue;
    }
    buckets[{layer, BucketKey{op.getName(), *secondaryKey}}].push_back(laneOp);
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
    for (QubitLaneOpInterface candidate : buckets[key]) {
      const int64_t width = getVectorLength(candidate);
      std::optional staticQubits = getStaticQubits(candidate);

      // A candidate whose qubits cannot be identified, or that exceeds the limit all by itself, never becomes a
      // member - not even the first one of a group.
      if (!staticQubits || width > limitVF) {
        close(group);
        continue;
      }

      // The group conditions (or empty).
      const bool emptyOrFits =
          group.members.empty() ||
          (group.width + width <= limitVF &&
           llvm::none_of(*staticQubits, [&](qco::StaticOp qubit) { return group.qubits.contains(qubit); }) &&
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
