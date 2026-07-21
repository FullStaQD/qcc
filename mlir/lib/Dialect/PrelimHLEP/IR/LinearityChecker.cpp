#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include <llvm/ADT/TypeSwitch.h>
#include <mlir/IR/DialectImplementation.h>
#include <mlir/Interfaces/ControlFlowInterfaces.h>
#include <mlir/Interfaces/FunctionInterfaces.h>

using namespace mlir;
using namespace qcc::prelimhlep;

namespace {
/// Returns the region that directly contains `value`'s definition (the
/// block's parent region for a block argument, or the defining op's parent
/// region for an op result).
Region* getDefiningRegion(Value value) {
  if (auto blockArg = dyn_cast<BlockArgument>(value)) {
    return blockArg.getOwner()->getParent();
  }
  return value.getDefiningOp()->getParentRegion();
}

/// Returns true if `user` may be reached a variable number of times (zero,
/// once, or many) relative to `defRegion`, because it is nested within a
/// repetitive (loop-like) region somewhere between `defRegion` and `user`.
bool mayExecuteRepeatedly(Operation* user, Region* defRegion) {
  for (Region* region = user->getParentRegion(); (region != nullptr) && region != defRegion;
       region = region->getParentOp()->getParentRegion()) {
    auto branchOp = dyn_cast<RegionBranchOpInterface>(region->getParentOp());
    if (branchOp && branchOp.isRepetitiveRegion(region->getRegionNumber())) {
      return true;
    }
  }
  return false;
}

/// Walks from `use`'s owning operation up toward `boundaryRegion`, returning
/// the branch op and its region that most tightly enclose `use` while still
/// being directly nested inside `boundaryRegion` -- i.e. the first branch op
/// reached when walking *down* from `boundaryRegion` toward `use` (which may
/// itself be nested arbitrarily deeper still, under further branch ops
/// inside that region). Regions whose parent op does *not* implement
/// `RegionBranchOpInterface` (like `prelim_hlep.lin`'s body) are
/// transparent: they always execute exactly once alongside their parent op,
/// so they don't affect whether a use is "direct" (unconditional) relative
/// to `boundaryRegion`.
///
/// Returns {nullptr, nullptr} if the use is direct, i.e. no branch op exists
/// between `boundaryRegion` and the use.
std::pair<Operation*, Region*> findEnclosingBranchAncestor(OpOperand* use, Region* boundaryRegion) {
  std::pair<Operation*, Region*> found = {nullptr, nullptr};
  for (Region* region = use->getOwner()->getParentRegion(); (region != nullptr) && region != boundaryRegion;
       region = region->getParentOp()->getParentRegion()) {
    if (isa<RegionBranchOpInterface>(region->getParentOp())) {
      // Keep overwriting: the last match found before reaching
      // `boundaryRegion` is the outermost one, i.e. the one directly nested
      // inside `boundaryRegion`.
      found = {region->getParentOp(), region};
    }
  }
  return found;
}

/// Returns a location to point to for `region` when reporting that it does
/// not use the checked value: the location of its first operation if it has
/// one, otherwise the parent op's location.
Location getRegionLoc(Region* region) {
  if (!region->empty() && !region->front().empty()) {
    return region->front().front().getLoc();
  }
  return region->getParentOp()->getLoc();
}

/// Attaches one note per distinct owning operation in `uses`, reporting how
/// many of the uses it accounts for. Uses are grouped by owner (rather than
/// emitting one identical "used here" note per use) so that e.g. two uses
/// that are both operands of the very same op -- which necessarily share a
/// location -- are reported as a single, distinguishable note.
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

LogicalResult checkUsesCoverRegion(Operation* diagOp, const Twine& description, Region* region,
                                   ArrayRef<OpOperand*> uses, bool isRegionUnconditional);

/// Handles the group of uses that are all nested (possibly transitively,
/// through further nested branch ops, and possibly transparently, see
/// `findEnclosingBranchAncestor`) in a distinct region of the same
/// `RegionBranchOpInterface` operation `branchOp` -- e.g. the `then`/`else`
/// regions of an `scf.if`. Succeeds only if every region of `branchOp` is
/// covered by at least one use, there is no control-flow path that can skip
/// `branchOp` entirely, the covered regions are pairwise proven mutually
/// exclusive, and -- recursively -- each region's own uses cover it with
/// exactly one use on every path through it (see `checkUsesCoverRegion`,
/// which handles any further nesting); otherwise emits a diagnostic on
/// `diagOp` (with `description` identifying the value) and fails.
LogicalResult checkBranchCoverage(Operation* diagOp, const Twine& description, Operation* branchOp,
                                  ArrayRef<std::pair<OpOperand*, Region*>> branchUses) {
  auto regionBranchOp = cast<RegionBranchOpInterface>(branchOp);
  SmallVector<RegionSuccessor> entrySuccessors;
  regionBranchOp.getSuccessorRegions(RegionBranchPoint::parent(), entrySuccessors);
  bool hasParentBypass = llvm::any_of(entrySuccessors, [](RegionSuccessor& s) { return s.isParent(); });

  SmallVector<std::pair<Region*, SmallVector<OpOperand*>>> byRegion;
  for (Region& region : branchOp->getRegions()) {
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
        failed(checkUsesCoverRegion(diagOp, description, region, regionUses, /*isRegionUnconditional=*/false))) {
      return failure();
    }
  }

  // The regions that do have uses must be pairwise mutually exclusive (one
  // representative use per region suffices, since this is a structural
  // property of the regions, not of the specific uses inside them).
  for (size_t i = 0, e = byRegion.size(); i < e; ++i) {
    if (byRegion[i].second.empty()) {
      continue;
    }
    for (size_t j = i + 1; j < e; ++j) {
      if (byRegion[j].second.empty()) {
        continue;
      }
      Operation* repA = byRegion[i].second.front()->getOwner();
      Operation* repB = byRegion[j].second.front()->getOwner();
      if (!insideMutuallyExclusiveRegions(repA, repB)) {
        auto diag = diagOp->emitError() << description
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
  bool allRegionsCovered = llvm::all_of(byRegion, [](const auto& p) { return !p.second.empty(); });
  if (!allRegionsCovered || hasParentBypass) {
    auto diag = diagOp->emitError() << description
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

/// Recursively determines whether `uses` -- known to be exactly the uses of
/// the checked value that are reached when control flow enters `region`
/// (possibly through several further levels of nested branch ops) -- use the
/// value exactly once on every control-flow path through `region`. `uses` is
/// never empty: an empty set for some control-flow path is instead reported
/// by the caller (see `checkBranchCoverage`), which only recurses into a
/// region once it knows at least one use reaches it.
///
/// This is the recursive core of the linearity analysis: relative to
/// `region`, it splits `uses` into those reached unconditionally within
/// `region` ("direct" uses) and those nested under branch ops directly
/// inside `region` (see `findEnclosingBranchAncestor`). A direct use
/// combined with any other use is an immediate double use. Otherwise, if all
/// remaining uses are (transitively) nested under arms of the same single
/// branch op, `checkBranchCoverage` recurses into each of its regions to
/// keep resolving any further nesting; uses spread across unrelated branch
/// ops are rejected, as this analysis cannot reason about them.
///
/// `isRegionUnconditional` distinguishes `region` being unconditionally
/// reached whenever the value is defined (the top-level call, from
/// `checkPreciselyOneUse`) from `region` itself being one arm of some
/// enclosing branch op (every recursive call), which only affects how
/// double-use diagnostics are phrased.
LogicalResult checkUsesCoverRegion(Operation* diagOp, const Twine& description, Region* region,
                                   ArrayRef<OpOperand*> uses, bool isRegionUnconditional) {
  unsigned directUses = 0;
  Operation* branchOp = nullptr;
  bool multipleBranchOps = false;
  SmallVector<std::pair<OpOperand*, Region*>> branchUses;
  for (OpOperand* use : uses) {
    auto [ancestorBranchOp, ancestorRegion] = findEnclosingBranchAncestor(use, region);
    if (ancestorBranchOp == nullptr) {
      ++directUses;
      continue;
    }
    if (branchOp == nullptr) {
      branchOp = ancestorBranchOp;
    } else if (branchOp != ancestorBranchOp) {
      multipleBranchOps = true;
    }
    branchUses.emplace_back(use, ancestorRegion);
  }

  // A use that always executes, combined with any other (possibly
  // conditional) use, is a proven double-use on whichever path also takes
  // the other use.
  if (directUses > 1 || (directUses == 1 && !branchUses.empty())) {
    auto diag = diagOp->emitError() << description << " is subject to linearity, but is used more than once";
    if (!isRegionUnconditional) {
      diag << " on this control-flow path";
    }
    attachUseNotes(diag, uses);
    return diag;
  }
  if (directUses == 1) {
    return success();
  }

  // All uses are conditional. This analysis only understands the case where
  // they are all arms of a single branch operation.
  if (multipleBranchOps) {
    auto diag =
        diagOp->emitError() << description
                            << " is subject to linearity, but its uses are spread across unrelated control-flow "
                               "branches, which this analysis cannot reason about";
    attachUseNotes(diag, uses);
    return diag;
  }
  return checkBranchCoverage(diagOp, description, branchOp, branchUses);
}

/// Tries to prove that `value` (identified as `description` in diagnostics,
/// e.g. "function argument #0") is used exactly once on every control-flow
/// path, emitting a diagnostic on `diagOp` and failing otherwise -- including
/// when the analysis simply cannot draw a conclusion (loops, unstructured
/// control flow, branch operations it doesn't understand, ...). This is a
/// best-effort analysis: it only ever accepts IR it can *positively prove*
/// linear, so extending it to understand more control-flow patterns can only
/// ever accept more (never less) IR.
LogicalResult checkPreciselyOneUse(Operation* diagOp, Value value, const Twine& description) {
  SmallVector<OpOperand*> uses;
  for (OpOperand& use : value.getUses()) {
    uses.push_back(&use);
  }

  if (uses.empty()) {
    return diagOp->emitError() << description << " is subject to linearity, but is never used";
  }

  Region* defRegion = getDefiningRegion(value);
  for (OpOperand* use : uses) {
    if (mayExecuteRepeatedly(use->getOwner(), defRegion)) {
      auto diag = diagOp->emitError() << description
                                      << " is subject to linearity, but is used inside a loop, where the "
                                         "number of dynamic uses cannot be determined statically";
      diag.attachNote(use->getOwner()->getLoc()) << "used here";
      return diag;
    }
  }

  return checkUsesCoverRegion(diagOp, description, defRegion, uses, /*isRegionUnconditional=*/true);
}

/// Returns true if `type` is not purely classical, i.e. subject to
/// linearity checking. For now this only recognizes `!prelim_hlep.lin<...>`
/// itself; it does not look inside aggregate types that might contain one.
/// Note that `!prelim_hlep.unit`, despite being the unit of the linear
/// product, is itself a purely classical type (isomorphic to `none`), and so
/// is not subject to linearity checking.
bool isNotPurelyClassical(Type type) { return isa<LinType>(type); }

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
} // namespace
