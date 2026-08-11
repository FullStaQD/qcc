#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include <llvm/ADT/TypeSwitch.h>
#include <mlir/IR/DialectImplementation.h>
#include <mlir/Interfaces/ControlFlowInterfaces.h>
#include <mlir/Interfaces/FunctionInterfaces.h>

using namespace mlir;
using namespace qcc::prelimhlep;

namespace {
Region* getDefiningRegion(Value value) {
  if (auto blockArg = dyn_cast<BlockArgument>(value)) {
    return blockArg.getOwner()->getParent();
  }
  return value.getDefiningOp()->getParentRegion();
}

Operation* getDefiningAnchorOp(Value value) {
  if (auto blockArg = dyn_cast<BlockArgument>(value)) {
    return blockArg.getOwner()->getParentOp();
  }
  return value.getDefiningOp();
}

bool mayExecuteRepeatedly(Operation* user, Region* scopeRegion) {
  for (Region* region = user->getParentRegion(); (region != nullptr) && region != scopeRegion;
       region = region->getParentOp()->getParentRegion()) {
    auto branchOp = dyn_cast<RegionBranchOpInterface>(region->getParentOp());
    if (branchOp && branchOp.isRepetitiveRegion(region->getRegionNumber())) {
      return true;
    }
  }
  return false;
}

/// Top-most `RegionBranchOpInterface` region enclosing `value` that is a child of `boundaryRegion`, or nullptr if none.
std::pair<Operation*, Region*> findEnclosingBranchAncestor(OpOperand* use, Region* boundaryRegion) {
  std::pair<Operation*, Region*> found = {nullptr, nullptr};
  for (Region* region = use->getOwner()->getParentRegion(); (region != nullptr) && region != boundaryRegion;
       region = region->getParentOp()->getParentRegion()) {
    if (isa<RegionBranchOpInterface>(region->getParentOp())) {
      found = {region->getParentOp(), region};
    }
  }
  return found;
}

LogicalResult checkUsesCoverRegion(const Twine& description, Region* region, ArrayRef<OpOperand*> uses,
                                   bool isRegionUnconditional);

/// Succeeds only if every branch of `branchOp` is
/// covered by at least one use, and -- recursively -- each region's own uses cover it with
/// exactly one use on every path through it; otherwise fails.
///
/// Recursive back-and-forth with `checkUsesCoverRegion`.
LogicalResult checkBranchCoverage(const Twine& description, Operation* branchOp,
                                  ArrayRef<std::pair<OpOperand*, Region*>> branchUses) {
  auto regionBranchOp = cast<RegionBranchOpInterface>(branchOp);
  SmallVector<RegionSuccessor> entrySuccessors;
  // TODO: I believe this checks e.g. for if-without-else. Double-check.
  regionBranchOp.getSuccessorRegions(RegionBranchPoint::parent(), entrySuccessors);
  bool hasParentBypass = llvm::any_of(entrySuccessors, [](RegionSuccessor& s) { return s.isParent(); });

  // Mapping Regions -> uses. Include regions with no uses.
  SmallVector<std::pair<Region*, SmallVector<OpOperand*>>>
      byRegion;                                   // TODO: Check if another type like DenseMap could fit here.
  for (Region& region : branchOp->getRegions()) { // TODO: Really we want to iterate over all successor regions, don't
                                                  // we? I don't think it makes a difference in practice.
    SmallVector<OpOperand*> regionUses;
    for (const auto& [use, useRegion] : branchUses) {
      if (useRegion == &region) {
        regionUses.push_back(use);
      }
    }
    byRegion.emplace_back(&region, std::move(regionUses));
  }

  // Recurse into every region that has at least one use first, so that a
  // double use (or further unresolvable nesting) confined to a single arm is
  // reported precisely, rather than being masked by a less specific
  // coverage-gap diagnostic about some other, entirely unused, arm.
  for (const auto& [region, regionUses] : byRegion) {
    if (!regionUses.empty() &&
        failed(checkUsesCoverRegion(description, region, regionUses, /*isRegionUnconditional=*/false))) {
      return failure();
    }
  }

  // We know here: Every region that has at least one use is covered by exactly one use on every control-flow path
  // through it.

  // The regions that do have uses must be pairwise mutually exclusive (one
  // representative use per region suffices, since this is a structural
  // property of the regions, not of the specific uses inside them).
  for (size_t i = 0, e = byRegion.size(); i < e; ++i) {
    const auto& [regionA, regionUsesA] = byRegion[i];
    if (regionUsesA.empty()) {
      continue;
    }
    for (size_t j = i + 1; j < e; ++j) {
      const auto& [regionB, regionUsesB] = byRegion[j];
      if (regionUsesB.empty()) {
        continue;
      }
      Operation* repA = regionUsesA.front()->getOwner();
      Operation* repB = regionUsesB.front()->getOwner();
      if (!insideMutuallyExclusiveRegions(repA, repB)) {
        auto diag = branchOp->emitError() << description
                                          << " is subject to linearity, but its uses could not be proven to lie on "
                                             "mutually exclusive control-flow paths";
        diag.attachNote(repA->getLoc()) << "used here";
        diag.attachNote(repB->getLoc()) << "and here";
        return diag;
      }
    }
  }

  // Every region of `branchOp` must be covered by at least one use; a region
  // with none is a control-flow path with zero uses of the value.
  // TODO: As before, this assumes that the regions of `branchOp` are exactly the successor regions, which is true for
  // `scf.if`.
  bool allRegionsCovered = llvm::all_of(byRegion, [](const auto& p) { return !p.second.empty(); });
  if (!allRegionsCovered || hasParentBypass) {
    // Anchor on the branch op itself: it's the specific construct that
    // introduces the uncovered control-flow path.
    auto diag = branchOp->emitError() << description
                                      << " is subject to linearity, but is not used on every control-flow path";
    for (const auto& [use, region] : branchUses) {
      diag.attachNote(use->getOwner()->getLoc()) << "used on this control-flow path";
    }
    for (const auto& [region, regionUses] : byRegion) {
      if (regionUses.empty()) {
        diag.attachNote(getRegionLoc(region)) << "not used on this control-flow path";
      }
    }
    if (hasParentBypass) {
      diag.attachNote(branchOp->getLoc()) << "control flow may also skip this operation entirely";
    }
    return diag;
  }

  return success();
}

/// Checks whether the uses of a value cover all control-flow paths through a region.
///
/// Recursive back-and-forth with `checkBranchCoverage`.
LogicalResult checkUsesCoverRegion(const Twine& description, Region* region, ArrayRef<OpOperand*> uses,
                                   bool isRegionUnconditional) {
  unsigned directUses = 0;       // Number of uses that are not nested under a branch.
  Operation* branchOp = nullptr; // The single branch op that all nested uses are under, if any.
  OpOperand* conflictingUse =
      nullptr; // A use that is under a different branch op than the others (unsupported), if any.
  SmallVector<std::pair<OpOperand*, Region*>> branchUses;
  for (OpOperand* use : uses) {
    auto [ancestorBranchOp, ancestorRegion] = findEnclosingBranchAncestor(use, region);
    if (ancestorBranchOp == nullptr) {
      ++directUses;
      continue;
    }
    if (branchOp == nullptr) {
      branchOp = ancestorBranchOp;
    } else if (branchOp != ancestorBranchOp && conflictingUse == nullptr) {
      conflictingUse = use;
    }
    branchUses.emplace_back(use, ancestorRegion);
  }

  // A use that always executes, combined with any other (possibly
  // conditional) use, is a proven double-use on whichever path also takes
  // the other use.
  if (directUses > 1 || (directUses == 1 && !branchUses.empty())) {
    auto diag = uses.back()->getOwner()->emitError()
                << description << " is subject to linearity, but is used more than once";
    if (!isRegionUnconditional) {
      diag << " on this control-flow path";
    }
    attachUseNotes(diag, uses);
    return diag;
  }
  if (directUses == 1) {
    return success();
  }

  // We know here: No direct uses.

  // All uses are conditional. This analysis only understands the case where
  // they are all arms of a single branch operation.
  if (conflictingUse != nullptr) {
    auto diag = conflictingUse->getOwner()->emitError()
                << description
                << " is subject to linearity, but its uses are spread across consecutive control-flow "
                   "branches, which cannot be proven to be mutually exclusive";
    attachUseNotes(diag, uses);
    return diag;
  }
  return checkBranchCoverage(description, branchOp, branchUses);
}

/// Tries to prove that `value` is used exactly once on every control-flow
/// path. Fails if it cannot be proven.
LogicalResult checkPreciselyOneUse(Value value, const Twine& description) {
  SmallVector<OpOperand*> uses;
  for (OpOperand& use : value.getUses()) {
    uses.push_back(&use);
  }

  if (uses.empty()) {
    return getDefiningAnchorOp(value)->emitError() << description << " is subject to linearity, but is never used";
  }

  Region* defRegion = getDefiningRegion(value);
  for (OpOperand* use : uses) {
    if (mayExecuteRepeatedly(use->getOwner(), defRegion)) {
      return use->getOwner()->emitError()
             << description
             << " is subject to linearity, but is used inside a loop, where the number of dynamic uses cannot be "
                "determined statically";
    }
  }

  return checkUsesCoverRegion(description, defRegion, uses, /*isRegionUnconditional=*/true);
}

/// Returns true if `type` is subject to
/// linearity checking. For now this only recognizes `!prelim_hlep.lin<...>`
/// itself.
bool isNotPurelyClassical(Type type) { return isa<LinType>(type); }

/// Returns true if `region` directly contains (not nested) a linear value.
bool regionHasLinearValue(Region& region) {
  for (Block& block : region) {
    if (llvm::any_of(block.getArgumentTypes(), isNotPurelyClassical)) {
      return true;
    }
    for (Operation& op : block) {
      if (llvm::any_of(op.getOperandTypes(), isNotPurelyClassical) ||
          llvm::any_of(op.getResultTypes(), isNotPurelyClassical)) {
        return true;
      }
    }
  }
  return false;
}

/// Verifies that every region (transitively) nested inside `op` that
/// contains a value subject to linearity checking (see
/// `regionHasLinearValue`) has exactly one block. `cf`-style multi-block regions
/// are not supported.
LogicalResult checkSingleBlockRegions(Operation* op, const Twine& haloAttrName) {
  LogicalResult result = success();
  op->walk([&](Operation* nestedOp) {
    for (Region& region : nestedOp->getRegions()) {
      if (!region.hasOneBlock() && !region.empty() && regionHasLinearValue(region)) {
        nestedOp->emitError() << "'" << haloAttrName
                              << "' function has a region with multiple blocks that uses a value subject to "
                                 "linearity; the linearity checker only understands structured control flow (e.g. "
                                 "'scf.if'), not unstructured, 'cf'-dialect-style branching between blocks of the "
                                 "same region";
        result = failure();
      }
    }
  });
  return result;
}

/// Verifies that no `SelectLikeOpInterface` op (e.g. `arith.select`)
/// anywhere (transitively) inside `op` has an operand or result of a type
/// subject to linearity checking.
LogicalResult checkNoSelectOfLinearValues(Operation* op, const Twine& haloAttrName) {
  LogicalResult result = success();
  op->walk([&](SelectLikeOpInterface selectOp) {
    if (llvm::any_of(selectOp->getOperandTypes(), isNotPurelyClassical) ||
        llvm::any_of(selectOp->getResultTypes(), isNotPurelyClassical)) {
      selectOp->emitError() << "'" << haloAttrName
                            << "' function uses a value subject to linearity as an operand or result of a "
                               "select-like op; only one of a select's operands is ever actually produced, but "
                               "both must exist unconditionally, so this analysis cannot prove the other one isn't "
                               "silently discarded";
      result = failure();
    }
  });
  return result;
}

// -------
// DIAGNOSTICS HELPERS
// -------

// TODO: These need declarations upfront. Create header?

/// Builds a human-readable description of `value` (a linearity-checked
/// function argument, block argument, or op result) for use in diagnostics.
std::string describeLinearValue(FunctionOpInterface funcOp, Value value) {
  if (auto blockArg = dyn_cast<BlockArgument>(value)) {
    if (blockArg.getOwner() == &funcOp.getFunctionBody().front()) {
      return ("function argument #" + Twine(blockArg.getArgNumber())).str();
    }
    return ("block argument #" + Twine(blockArg.getArgNumber())).str();
  }
  OpResult result = cast<OpResult>(value);
  return ("result #" + Twine(result.getResultNumber()) + " of '" + result.getOwner()->getName().getStringRef() + "'")
      .str();
}

Location getRegionLoc(Region* region) {
  if (!region->empty() && !region->front().empty()) {
    return region->front().front().getLoc();
  }
  return region->getParentOp()->getLoc();
}

void attachUseNotes(InFlightDiagnostic& diag, ArrayRef<OpOperand*> uses) {
  SmallVector<std::pair<Operation*, unsigned>> counts;
  for (OpOperand* use : uses) {
    Operation* owner = use->getOwner();
    auto* it = llvm::find_if(counts, [&](auto& p) { return p.first == owner; });
    if (it == counts.end()) {
      counts.emplace_back(owner, 1);
    } else {
      ++it->second;
    }
  }
  for (auto& [owner, count] : counts) {
    if (count > 1) {
      diag.attachNote(owner->getLoc()) << "used " << count << " times here";
    } else {
      diag.attachNote(owner->getLoc()) << "used here";
    }
  }
}

} // namespace
