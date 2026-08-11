#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include <llvm/ADT/TypeSwitch.h>
#include <mlir/IR/DialectImplementation.h>
#include <mlir/Interfaces/ControlFlowInterfaces.h>
#include <mlir/Interfaces/FunctionInterfaces.h>

using namespace mlir;
using namespace qcc::prelimhlep;

namespace {

// Forward declarations of the diagnostics helpers defined at the bottom of
// this file. They cannot live in a header: this file is textually included
// into `PrelimHLEPDialect.cpp` and everything in it has internal linkage.
std::string describeLinearValue(FunctionOpInterface funcOp, Value value);
Location getRegionLoc(Region* region);
void attachUseNotes(InFlightDiagnostic& diag, ArrayRef<OpOperand*> uses);

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

/// Bitmask of the numbers of uses that may have accumulated at some point of
/// the control flow through a branch op, saturating at "two or more" (which is
/// already a linearity violation, so the exact number stops mattering).
///
/// Example usage: `(counts | kOneUse) & (counts | kTwoOrMoreUses)` means that
/// there exists a path with one use and a path with two or more uses.
enum UseCounts : unsigned {
  kNoPath = 0,
  kZeroUses = 1U << 0,
  kOneUse = 1U << 1,
  kTwoOrMoreUses = 1U << 2,
};

/// Adds one use to every count in `counts`.
UseCounts addOneUse(UseCounts counts) {
  unsigned result = 0;
  if ((counts & kZeroUses) != 0) {
    result |= kOneUse;
  }
  if ((counts & (kOneUse | kTwoOrMoreUses)) != 0) {
    result |= kTwoOrMoreUses;
  }
  return static_cast<UseCounts>(result);
}

/// Appends the control-flow successors of `region` -- another region of the
/// same op, or the parent op itself -- to `successors`.
///
/// This is `RegionBranchOpInterface::getSuccessorRegions(Region&, ...)` plus
/// the convention that a block whose terminator does not implement
/// `RegionBranchTerminatorOpInterface` (`scf.yield`, for instance) returns to
/// the parent op. That convention is what upstream's own region-graph
/// traversals assume, and erring towards *more* edges is the safe direction
/// here: extra edges can only make the check below reject more.
void getRegionSuccessors(RegionBranchOpInterface branchOp, Region* region,
                         SmallVectorImpl<RegionSuccessor>& successors) {
  for (Block& block : *region) {
    if (block.empty()) {
      continue;
    }
    auto terminator = dyn_cast<RegionBranchTerminatorOpInterface>(block.back());
    if (!terminator) {
      successors.emplace_back(branchOp, branchOp->getResults());
      continue;
    }
    branchOp.getSuccessorRegions(RegionBranchPoint(terminator), successors);
  }
}

/// Succeeds only if every control-flow path through `branchOp` carries exactly
/// one use of the value, and -- recursively -- each region's own uses cover it
/// with exactly one use on every path through it; otherwise fails.
///
/// Recursive back-and-forth with `checkUsesCoverRegion`.
LogicalResult checkBranchCoverage(const Twine& description, Operation* branchOp,
                                  ArrayRef<std::pair<OpOperand*, Region*>> branchUses) {
  auto regionBranchOp = cast<RegionBranchOpInterface>(branchOp);

  // Mapping Regions -> uses, for the regions that have any. A vector (rather
  // than a map) keeps the diagnostics below deterministically ordered, and it
  // holds one entry per region actually mentioning the value.
  SmallVector<std::pair<Region*, SmallVector<OpOperand*>>> byRegion;
  for (const auto& [use, useRegion] : branchUses) {
    auto* it = llvm::find_if(byRegion, [&](const auto& p) { return p.first == useRegion; });
    if (it == byRegion.end()) {
      byRegion.emplace_back(useRegion, SmallVector<OpOperand*>{use});
    } else {
      it->second.push_back(use);
    }
  }

  // Recurse into every region that has at least one use first, so that a
  // double use (or further unresolvable nesting) confined to a single region
  // is reported precisely, rather than being masked by a less specific
  // coverage-gap diagnostic about the op as a whole.
  for (const auto& [region, regionUses] : byRegion) {
    if (failed(checkUsesCoverRegion(description, region, regionUses, /*isRegionUnconditional=*/false))) {
      return failure();
    }
  }

  // We know here: every region that has at least one use contributes exactly
  // one use whenever control flow passes through it.
  // Therefore `usesValue` means "uses value exactly once".
  auto usesValue = [&byRegion](Region* region) {
    return llvm::any_of(byRegion, [&](const auto& p) { return p.first == region; });
  };

  // Forward propagation over the region successor graph. `incoming` maps a
  // region to the counts control flow may have accumulated when *entering* it;
  // `exitCounts` collects the counts of the paths leaving the op. The masks
  // only ever grow, so the fixpoint is reached in bounded time.
  DenseMap<Region*, UseCounts> incoming;
  SmallVector<Region*> visitOrder; // Deterministic order for the diagnostics.
  SmallVector<Region*> worklist;
  UseCounts exitCounts = kNoPath;
  auto propagate = [&](const RegionSuccessor& successor, UseCounts counts) {
    Region* target = successor.getSuccessor();
    if (target == nullptr) { // The parent op itself, i.e. a path leaving the op.
      exitCounts = static_cast<UseCounts>(exitCounts | counts);
      return;
    }
    auto [it, inserted] = incoming.try_emplace(target, kNoPath);
    auto& targetCounts = it->second;
    if (inserted) {
      visitOrder.push_back(target);
    }
    if ((targetCounts | counts) == targetCounts) {
      return;
    }
    targetCounts = static_cast<UseCounts>(targetCounts | counts);
    worklist.push_back(target);
  };

  SmallVector<RegionSuccessor> successors;
  regionBranchOp.getSuccessorRegions(RegionBranchPoint::parent(), successors);
  // An entry successor that is the parent op means control flow can skip all
  // regions of `branchOp` and go straight to its results -- an `scf.if`
  // without an `else` region, for instance, lists its parent as an entry
  // successor.
  bool hasParentBypass = llvm::any_of(successors, [](RegionSuccessor& s) { return s.isParent(); });
  for (const RegionSuccessor& successor : successors) {
    propagate(successor, kZeroUses); // Initializes the worklist.
  }
  while (!worklist.empty()) {
    Region* region = worklist.pop_back_val();
    UseCounts leaving = usesValue(region) ? addOneUse(incoming[region]) : incoming[region];
    successors.clear();
    getRegionSuccessors(regionBranchOp, region, successors);
    for (const RegionSuccessor& successor : successors) {
      propagate(successor, leaving); // Also adds the successors to the worklist if their counts changed.
    }
  }

  // The counts each region *leaves* with, for the diagnostics below.
  DenseMap<Region*, UseCounts> outgoing;
  for (Region* region : visitOrder) {
    outgoing[region] = usesValue(region) ? addOneUse(incoming[region]) : incoming[region];
  }

  // A use in a region the propagation never reached is a use the analysis has
  // not accounted for, so it cannot claim the value is used exactly once.
  for (const auto& [region, regionUses] : byRegion) {
    if (!incoming.contains(region)) {
      auto diag = branchOp->emitError() << description
                                        << " is subject to linearity, but is used inside a region that this "
                                           "operation does not report as reachable by its control flow";
      diag.attachNote(getRegionLoc(region)) << "used in this region";
      return diag;
    }
  }

  if ((exitCounts & kTwoOrMoreUses) != 0) {
    // Anchor on the branch op: no single use is at fault, it is the
    // combination of uses across its regions that double-uses the value.
    auto diag = branchOp->emitError()
                << description
                << " is subject to linearity, but is used more than once on a control-flow path through this operation";
    SmallVector<OpOperand*> uses;
    for (const auto& [use, region] : branchUses) {
      uses.push_back(use);
    }
    attachUseNotes(diag, uses);
    return diag;
  }

  if ((exitCounts & kZeroUses) != 0) {
    // Anchor on the branch op itself: it's the specific construct that
    // introduces the uncovered control-flow path.
    auto diag = branchOp->emitError() << description
                                      << " is subject to linearity, but is not used on every control-flow path";
    for (const auto& [use, region] : branchUses) {
      diag.attachNote(use->getOwner()->getLoc()) << "used on this control-flow path";
    }
    // Point at the regions a use-free path runs through on its way out of the
    // op -- these are exactly the places where adding the missing use would
    // close the gap. (A region that uses the value never leaves with a count
    // of zero, so it is never among them.) In the "if-then-else-finally" shape
    // with a use only in `then`, that is both `else` and `finally`; for an
    // `scf.if`, it is just the arm that is missing the use.
    SmallPtrSet<Region*, 4> onUseFreeExitPath;
    for (bool changed = true; changed;) {
      changed = false;
      for (Region* region : visitOrder) {
        if ((outgoing[region] & kZeroUses) == 0 || onUseFreeExitPath.contains(region)) {
          continue;
        }
        successors.clear();
        getRegionSuccessors(regionBranchOp, region, successors);
        bool leadsOutWithoutUse = llvm::any_of(successors, [&](RegionSuccessor& s) {
          return s.isParent() || onUseFreeExitPath.contains(s.getSuccessor());
        });
        if (leadsOutWithoutUse) {
          onUseFreeExitPath.insert(region);
          changed = true;
        }
      }
    }
    for (Region* region : visitOrder) {
      if (onUseFreeExitPath.contains(region)) {
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
// (Declared at the top of this file, since the checks above use them.)

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
