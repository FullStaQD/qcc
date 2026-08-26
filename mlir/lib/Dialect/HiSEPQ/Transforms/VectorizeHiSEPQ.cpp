// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/HiSEPQ/HiSEPQHardware.h"
#include "qcc/Dialect/HiSEPQ/IR/HiSEPQ.h"
#include "qcc/Dialect/HiSEPQ/Transforms/Passes.h" // IWYU pragma: keep

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
#include "mlir/IR/ValueRange.h"
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
#include <utility>

using namespace mlir;
using namespace qcc::hisepq;

namespace {

//===----------------------------------------------------------------------===//
// A uniform view of the three HiSEP-Q operations
//===----------------------------------------------------------------------===//

using QubitOperands = SmallVector<TypedValue<VectorType>, 2>;

/// The qubit vectors `op` consumes, in operand order, or empty if `op` is not a quantum vector op.
///
/// `hisepq.pair` has two of them, everything else one. Element `i` of each vector belongs to the
/// same gate, which is what makes packing a matter of concatenating the vectors slot by slot.
QubitOperands getQubitOperands(Operation* op) {
  return TypeSwitch<Operation*, QubitOperands>(op)
      .Case([](SingleOp singleOp) { return QubitOperands{singleOp.getQubitsIn()}; })
      .Case([](PairOp pairOp) { return QubitOperands{pairOp.getCtrlsIn(), pairOp.getTgtsIn()}; })
      .Case([](MzOp mzOp) { return QubitOperands{mzOp.getQubitsIn()}; })
      .Default([](Operation*) { return QubitOperands{}; });
} // FIXME: Might want to replace this with an OpInterface

/// SingleOp, PairOp, or MzOp.
bool isVectorizableOp(Operation* op) { return isa_and_present<SingleOp, PairOp, MzOp>(op); }

/// The number of qubits one operand vector of `op` carries, i.e. the op's current VF.
int64_t getVectorLength(Operation* op) {
  return cast<VectorType>(getQubitOperands(op).front().getType()).getNumElements();
} // FIXME: Via OpInterface?

/// Identical bucket key for two ops expresses the fact that they can be merged
/// in vectorization. Format (op category, gate id if applicable), e.g. (single,
/// int(h)).
using BucketKey = std::pair<OperationName, uint32_t>;

// FIXME: better via OpInterface?
BucketKey getBucketKey(Operation* op) {
  const uint32_t gate = TypeSwitch<Operation*, uint32_t>(op)
                            .Case([](SingleOp singleOp) { return static_cast<uint32_t>(singleOp.getGate()); })
                            .Case([](PairOp pairOp) { return static_cast<uint32_t>(pairOp.getGate()); })
                            .Default([](Operation*) { return 0U; }); // FIXME: implicitly assumes Default == MZ.
  return {op->getName(), gate};
}

//===----------------------------------------------------------------------===//
// Scheduling helpers
//===----------------------------------------------------------------------===//

/// The `hisepq` operations that produced any element of `qubits`.
///
/// Walks back through everything that only moves qubits around, so it sees the producer even
/// when the vector was taken apart and put back together in between.
void collectProducers(Value qubits, SmallPtrSetImpl<Operation*>& producers) {
  Operation* definingOp = qubits.getDefiningOp();
  if (definingOp == nullptr) {
    return;
  }
  if (isVectorizableOp(definingOp)) {
    producers.insert(definingOp);
    return;
  }

  // FIXME: refactor this.
  TypeSwitch<Operation*>(definingOp)
      .Case<vector::FromElementsOp>([&](vector::FromElementsOp fromElementsOp) {
        for (auto element : fromElementsOp.getElements()) {
          collectProducers(element, producers);
        }
      })
      .Case<vector::ExtractOp, vector::BroadcastOp, vector::ShapeCastOp>(
          [&](auto op) { collectProducers(op.getSource(), producers); }) // FIXME: really need ShapeCastOp here?
      .Default([](Operation*) {});                                       // FIXME: be explicit here.
}

/// Makes `value` available at `before`, hoisting whatever defines it if it is not already.
///
/// Only pure operations are hoisted, and only within `before`'s block; anything else either
/// already dominates `before` or makes this fail. Hoisting a pure operation is always safe on its
/// own, so a failure part-way through leaves correct -- if pointlessly rearranged -- IR behind.
bool makeAvailableBefore(Value value, Operation* before) {
  Operation* definingOp = value.getDefiningOp();
  if (definingOp == nullptr || definingOp->getBlock() != before->getBlock()) {
    return true; // A block argument, or defined in an enclosing region. Either way it dominates.
  }
  if (definingOp->isBeforeInBlock(before)) {
    return true;
  }
  if (!isPure(definingOp)) {
    return false;
  }

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

/// The operations supposed to be merged into one, plus what the admission test needs.
struct Group {
  SmallVector<Operation*> members;
  /// Total number of qubits per operand slot, i.e. the VF the merged operation would have.
  int64_t width = 0;
  /// The qubits the group acts on, i.e. the merged operations would have.
  DenseSet<Value> qubits; // FIXME: TypedValue of Qubit?

  /// Build the first (slot=0) or second (slot=1, if available) qubit vector operand for the merged operation by
  /// collecting each member's qubits in the same slots.
  Value buildMergedOperand(OpBuilder& builder, Location loc, unsigned slot) const {
    assert(slot == 0 || slot == 1 && "slot can only be 0 or 1");
    SmallVector<Value> elements;
    for (Operation* member : this->members) {
      Value operand = getQubitOperands(member)[slot];
      for (int64_t index = 0; index < cast<VectorType>(operand.getType()).getNumElements(); ++index) {
        elements.push_back(vector::ExtractOp::create(builder, loc, operand, index));
      }
    }

    auto vectorType = VectorType::get({this->width}, elements.front().getType());
    return vector::FromElementsOp::create(builder, loc, vectorType, elements);
  }
};

/// The qubits `op` names, or nullopt if any of them cannot be identified.
///
/// Identity of the returned values is qubit identity, so this is what the overlap test compares.
/// An unidentifiable element makes the test impossible rather than false, hence the failure.
std::optional<SmallVector<Value>> getNamedQubits(Operation* op) {
  SmallVector<Value> qubits;
  for (auto operand : getQubitOperands(op)) {
    for (int64_t index = 0; index < cast<VectorType>(operand.getType()).getNumElements(); ++index) {
      qco::StaticOp staticOp = getStaticOpAncestor(operand, index);
      if (!staticOp) {
        return std::nullopt;
      }
      qubits.push_back(staticOp.getQubit());
    }
  }
  return qubits;
}

/// Extracts elements `[offset, offset + width)` out of `merged` as a vector of its own.
///
/// Use case: To enable the users of group members (which are now merged) to act on the right slice.
Value buildMemberSlice(OpBuilder& builder, Location loc, Value merged, int64_t offset, int64_t width) {
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
void mergeGroup(const Group& group) {
  Operation* firstOp = group.members.front();
  OpBuilder builder(firstOp); // important: sets insertion point right before firstOp.
  Location loc = firstOp->getLoc();

  SmallVector<Value, 2> operands;
  for (unsigned slot = 0; slot < getQubitOperands(firstOp).size(); ++slot) {
    operands.push_back(group.buildMergedOperand(builder, loc, slot));
  }

  Operation* merged =
      TypeSwitch<Operation*, Operation*>(firstOp)
          .Case([&](SingleOp singleOp) {
            return SingleOp::create(builder, loc, operands[0].getType(), singleOp.getGate(), operands[0]);
          })
          .Case([&](PairOp pairOp) {
            return PairOp::create(builder, loc, operands[0].getType(), operands[1].getType(), pairOp.getGate(),
                                  operands[0], operands[1]);
          })
          .Case([&](MzOp) {
            auto bitsType = VectorType::get({group.width}, builder.getI1Type());
            return MzOp::create(builder, loc, operands[0].getType(), bitsType, operands[0]);
          });

  // Replace uses of members by our newly created merged op.
  int64_t offset = 0;
  for (Operation* member : group.members) {
    const int64_t width = getVectorLength(member);
    SmallVector<Value> replacements;
    for (Value result : merged->getResults()) {
      replacements.push_back(buildMemberSlice(builder, member->getLoc(), result, offset, width));
    }
    member->replaceAllUsesWith(replacements);
    offset += width;
  }

  for (Operation* member : group.members) {
    member->erase();
  }
}

/// Packs one block's `hisepq` operations, up to `limitVF` qubits per operation.
void vectorizeBlock(Block& block, int64_t limitVF) {
  // Layering. layer(op) = 1 + max(layer(op_pred) for all predecessors op_pred of op).
  DenseMap<Operation*, unsigned> layers;
  llvm::MapVector<std::pair<unsigned, BucketKey>, SmallVector<Operation*>> buckets;
  for (Operation& op : block) {
    if (!isVectorizableOp(&op)) {
      continue;
    }

    SmallPtrSet<Operation*, 4> producers;
    for (auto operand : getQubitOperands(&op)) {
      collectProducers(operand, producers);
    }

    unsigned layer = 0;
    for (Operation* producer : producers) {
      auto it = layers.find(producer);
      if (it != layers.end()) {
        layer = std::max(layer, it->second + 1);
      }
    }

    layers[&op] = layer;
    buckets[{layer, getBucketKey(&op)}].push_back(&op);
  }

  // Sort keys by layer index (ascending).
  SmallVector<std::pair<unsigned, BucketKey>> keys = llvm::to_vector(llvm::make_first_range(buckets));
  llvm::stable_sort(keys, [](const auto& lhs, const auto& rhs) { return lhs.first < rhs.first; });

  auto close = [](Group& group) {
    if (group.members.size() > 1) {
      mergeGroup(group);
    }
    group = Group{};
  };

  for (const auto& key : keys) {
    Group group;
    for (Operation* candidate : buckets[key]) {
      const int64_t width = getVectorLength(candidate);
      std::optional<SmallVector<Value>> qubits = getNamedQubits(candidate);

      // FIXME: this none_of check, shouldn't it always be true?
      const bool fits = !group.members.empty() && group.width + width <= limitVF && qubits &&
                        llvm::none_of(*qubits, [&](Value qubit) { return group.qubits.contains(qubit); }) &&
                        llvm::all_of(getQubitOperands(candidate), [&](Value operand) {
                          return makeAvailableBefore(operand, group.members.front());
                        });

      if (!fits) {
        close(group);
        // A candidate whose qubits cannot be identified, or that is already too wide, starts no
        // group of its own either.
        if (!qubits || width > limitVF) {
          continue; // FIXME: shouldn't we error out here? Looks like a bug.
        }
      }

      group.members.push_back(candidate);
      group.width += width;
      group.qubits.insert_range(*qubits);
    }
    close(group);
  }
}

} // namespace

namespace qcc {

#define GEN_PASS_DEF_VECTORIZEHISEPQ
#include "qcc/Dialect/HiSEPQ/Transforms/Passes.h.inc"

namespace {

struct VectorizeHiSEPQ final : impl::VectorizeHiSEPQBase<VectorizeHiSEPQ> {
  using VectorizeHiSEPQBase::VectorizeHiSEPQBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();
    auto* ctx = moduleOp.getContext();

    // The max-vf option can only narrow VF (vectorization factor).
    const Hardware hardware = Hardware::fromModule(moduleOp);
    const unsigned limitVF = maxVF == 0 ? hardware.maxQubits() : std::min<unsigned>(maxVF, hardware.maxQubits());

    SmallVector<Block*> blocks;
    moduleOp->walk([&](Block* block) { blocks.push_back(block); });
    for (Block* block : blocks) {
      vectorizeBlock(*block, limitVF);
    }

    // Packing takes a qubit vector apart element by element and immediately puts it back together
    // again. This leads to verbose IR which we canonicalize (and simplify) here.
    RewritePatternSet patterns(ctx);
    vector::FromElementsOp::getCanonicalizationPatterns(patterns, ctx);
    if (failed(applyPatternsGreedily(moduleOp, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
