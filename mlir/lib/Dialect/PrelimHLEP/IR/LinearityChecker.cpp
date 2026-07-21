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

/// Walks up from `use`'s owning region to `defRegion`, looking for the
/// nearest ancestor operation that implements `RegionBranchOpInterface`
/// (i.e. the innermost structured-control-flow op the use is conditionally
/// nested under, if any). Regions whose parent op does *not* implement the
/// interface (like `prelim_hlep.lin`'s body) are transparent: they always
/// execute exactly once alongside their parent op, so they don't affect
/// whether a use is "direct" (unconditional) relative to `defRegion`.
///
/// Returns {nullptr, nullptr} if the use is direct, i.e. no such ancestor
/// exists between `defRegion` and the use.
std::pair<Operation*, Region*> findNearestBranchAncestor(OpOperand* use, Region* defRegion) {
  for (Region* region = use->getOwner()->getParentRegion(); (region != nullptr) && region != defRegion;
       region = region->getParentOp()->getParentRegion()) {
    if (isa<RegionBranchOpInterface>(region->getParentOp())) {
      return {region->getParentOp(), region};
    }
  }
  return {nullptr, nullptr};
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

/// Handles the group of uses that are all nested (possibly transparently, see
/// `findNearestBranchAncestor`) in a distinct region of the same
/// `RegionBranchOpInterface` operation `branchOp` -- e.g. the `then`/`else`
/// regions of an `scf.if`. Succeeds only if every region of `branchOp`
/// contains exactly one use and there is no control-flow path that can skip
/// all of them; otherwise emits a diagnostic on `diagOp` (with `description`
/// identifying the value) pointing at every relevant location and fails.
LogicalResult checkBranchCoverage(Operation* diagOp, const Twine& description, Operation* branchOp,
                                  ArrayRef<std::pair<OpOperand*, Region*>> branchUses) {
  for (size_t i = 0, e = branchUses.size(); i < e; ++i) {
    for (size_t j = i + 1; j < e; ++j) {
      if (branchUses[i].second == branchUses[j].second) {
        auto diag = diagOp->emitError() << description
                                        << " is subject to linearity, but is used more than once "
                                           "on this control-flow path";
        diag.attachNote(branchUses[i].first->getOwner()->getLoc()) << "used here";
        diag.attachNote(branchUses[j].first->getOwner()->getLoc()) << "and here";
        return diag;
      }
      if (!insideMutuallyExclusiveRegions(branchUses[i].first->getOwner(), branchUses[j].first->getOwner())) {
        auto diag = diagOp->emitError() << description
                                        << " is subject to linearity, but its uses could not be proven to lie on "
                                           "mutually exclusive control-flow paths";
        diag.attachNote(branchUses[i].first->getOwner()->getLoc()) << "used here";
        diag.attachNote(branchUses[j].first->getOwner()->getLoc()) << "and here";
        return diag;
      }
    }
  }

  // Every region of `branchOp` must have exactly one use; a region with none
  // is a control-flow path with zero uses of the value.
  auto regionBranchOp = cast<RegionBranchOpInterface>(branchOp);
  SmallVector<RegionSuccessor> entrySuccessors;
  regionBranchOp.getSuccessorRegions(RegionBranchPoint::parent(), entrySuccessors);
  bool hasParentBypass = llvm::any_of(entrySuccessors, [](RegionSuccessor& s) { return s.isParent(); });

  if (branchUses.size() < branchOp->getNumRegions() || hasParentBypass) {
    auto diag = diagOp->emitError() << description
                                    << " is subject to linearity, but is not used on every control-flow path";
    for (const auto& [use, region] : branchUses) {
      diag.attachNote(use->getOwner()->getLoc()) << "used on this control-flow path";
    }
    for (Region& region : branchOp->getRegions()) {
      bool used = llvm::any_of(branchUses, [&](auto& pair) { return pair.second == &region; });
      if (!used) {
        diag.attachNote(getRegionLoc(&region)) << "not used on this control-flow path";
      }
    }
    if (hasParentBypass) {
      diag.attachNote(branchOp->getLoc()) << "control flow may also skip this operation entirely";
    }
    return diag;
  }

  return success();
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

  // Split the uses into those reached unconditionally (relative to
  // `defRegion`) and those (transitively) nested under some branch op.
  unsigned directUses = 0;
  Operation* branchOp = nullptr;
  bool multipleBranchOps = false;
  SmallVector<std::pair<OpOperand*, Region*>> branchUses;
  for (OpOperand* use : uses) {
    auto [ancestorBranchOp, ancestorRegion] = findNearestBranchAncestor(use, defRegion);
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
  // TODO: I believe we can handle nested branching as follows: traverse the tree of branch ops upwards. All branches of
  // all of these branch ops must have exactly one use, and the union of all of these uses must be all uses of the
  // value. It suffices to check this for the first use.

  // A use that always executes, combined with any other (possibly
  // conditional) use, is a proven double-use on whichever path also takes
  // the other use.
  if (directUses > 1 || (directUses == 1 && !branchUses.empty())) {
    auto diag = diagOp->emitError() << description << " is subject to linearity, but is used more than once";
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
