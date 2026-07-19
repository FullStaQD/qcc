#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include <llvm/ADT/TypeSwitch.h>
#include <mlir/IR/DialectImplementation.h>
#include <mlir/Interfaces/ControlFlowInterfaces.h>
#include <mlir/Interfaces/FunctionInterfaces.h>

using namespace mlir;
using namespace qcc::prelimhlep;

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPDialect.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPTypes.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPAttrs.cpp.inc"

#define GET_OP_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPOps.cpp.inc"

/// Checks that `op` is nested (directly or indirectly) within a
/// `prelim_hlep.halo`-attributed function: walks up ancestor operations, and
/// requires that the first one implementing `FunctionOpInterface` carries
/// the halo attribute.
static LogicalResult verifyWithinHaloedFunction(Operation* op) {
  std::string haloAttrName = (PrelimHLEPDialect::getDialectNamespace() + "." + HaloAttr::getMnemonic()).str();

  auto funcOp = op->getParentOfType<FunctionOpInterface>();
  if (!funcOp || !funcOp->hasAttr(haloAttrName)) {
    return op->emitOpError("expected to be nested within a '") << haloAttrName << "'-attributed function";
  }

  return success();
}

LogicalResult ScaleOp::verify() { return verifyWithinHaloedFunction(getOperation()); }

LogicalResult AddPhaseOp::verify() { return verifyWithinHaloedFunction(getOperation()); }

LogicalResult BaseChangeOp::verify() { return verifyWithinHaloedFunction(getOperation()); }

LogicalResult OutputOp::verify() { return verifyWithinHaloedFunction(getOperation()); }

// Parses `( %arg : argType from %operand : operandType, ... ) -> ( resultType, ... ) region`.
ParseResult LinOp::parse(OpAsmParser& parser, OperationState& result) {
  SmallVector<OpAsmParser::Argument> blockArgs;
  SmallVector<OpAsmParser::UnresolvedOperand> operands;
  SmallVector<Type> operandTypes;

  auto parseBinding = [&]() -> ParseResult {
    OpAsmParser::Argument& blockArg = blockArgs.emplace_back();
    if (parser.parseArgument(blockArg, /*allowType=*/true) || parser.parseKeyword("from")) {
      return failure();
    }

    OpAsmParser::UnresolvedOperand& operand = operands.emplace_back();
    Type& operandType = operandTypes.emplace_back();
    return failure(parser.parseOperand(operand) || parser.parseColonType(operandType));
  };
  if (parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren, parseBinding)) {
    return failure();
  }

  SmallVector<Type> resultTypes;
  if (parser.parseArrow() || parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren, [&]() {
        return parser.parseType(resultTypes.emplace_back());
      })) {
    return failure();
  }
  result.addTypes(resultTypes);

  Region* body = result.addRegion();
  if (parser.parseRegion(*body, blockArgs)) {
    return failure();
  }

  if (parser.resolveOperands(operands, operandTypes, parser.getCurrentLocation(), result.operands)) {
    return failure();
  }

  return parser.parseOptionalAttrDict(result.attributes);
}

void LinOp::print(OpAsmPrinter& p) {
  p << " (";
  llvm::interleaveComma(llvm::zip(getBody().front().getArguments(), getDelinearizedOperands()), p,
                        [&](const auto& binding) {
                          BlockArgument arg = std::get<0>(binding);
                          Value operand = std::get<1>(binding);
                          p << arg << " : " << arg.getType() << " from " << operand << " : " << operand.getType();
                        });
  p << ") -> (";
  llvm::interleaveComma(getResultTypes(), p);
  p << ") ";
  p.printRegion(getBody(), /*printEntryBlockArgs=*/false);
  p.printOptionalAttrDict((*this)->getAttrs());
}

LogicalResult LinOp::verify() {
  if (failed(verifyWithinHaloedFunction(getOperation()))) {
    return failure();
  }

  Block& body = getBody().front();

  if (body.getNumArguments() != getDelinearizedOperands().size()) {
    return emitOpError("expected the body block to have as many arguments (")
           << body.getNumArguments() << ") as delinearized operands (" << getDelinearizedOperands().size() << ")";
  }

  for (unsigned i = 0, e = body.getNumArguments(); i < e; ++i) {
    Type elementType = dyn_cast<LinType>(getDelinearizedOperands()[i].getType()).getElementType();
    Type argType = body.getArgument(i).getType();
    if (argType != elementType) {
      return emitOpError("body block argument #")
             << i << " has type " << argType << ", expected the delinearized operand's element type " << elementType;
    }
  }

  auto output = dyn_cast<OutputOp>(body.getTerminator());
  if (!output) {
    return emitOpError("expected the body to be terminated with "
                       "'prelim_hlep.output'");
  }

  ValueRange delinearizedResults = output.getDelinearizedResults();
  ValueRange auxiliaryResults = output.getAuxiliaryResults();
  ResultRange results = getResults();
  if (results.size() != delinearizedResults.size() + auxiliaryResults.size()) {
    return emitOpError("expected ") << (delinearizedResults.size() + auxiliaryResults.size())
                                    << " results to match the number of 'prelim_hlep.output' "
                                       "operands, got "
                                    << results.size();
  }

  for (unsigned i = 0, e = delinearizedResults.size(); i < e; ++i) {
    auto resultType = dyn_cast<LinType>(results[i].getType());
    Type delinearizedType = delinearizedResults[i].getType();
    if (!resultType || resultType.getElementType() != delinearizedType) {
      return emitOpError("result #") << i << " has type " << results[i].getType()
                                     << ", expected the linearization of 'prelim_hlep.output' "
                                        "operand type "
                                     << delinearizedType;
    }
  }

  for (unsigned i = 0, e = auxiliaryResults.size(); i < e; ++i) {
    unsigned resultIdx = delinearizedResults.size() + i;
    Type auxType = auxiliaryResults[i].getType();
    if (results[resultIdx].getType() != auxType) {
      return emitOpError("result #") << resultIdx << " has type " << results[resultIdx].getType()
                                     << ", expected 'prelim_hlep.output' auxiliary operand type " << auxType;
    }
  }

  return success();
}

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
} // namespace

LogicalResult PrelimHLEPDialect::verifyOperationAttribute(Operation* op, NamedAttribute attribute) {
  std::string haloAttrName = (getNamespace() + "." + HaloAttr::getMnemonic()).str();
  if (attribute.getName() != haloAttrName) {
    return success();
  }

  auto funcOp = dyn_cast<FunctionOpInterface>(op);
  if (!funcOp) {
    return op->emitError("'") << haloAttrName << "' is only valid on function-like operations";
  }

  if (funcOp.getNumArguments() == 0) {
    return op->emitError("'") << haloAttrName
                              << "' function must not have zero arguments; use "
                                 "'!prelim_hlep.linear_unit' instead";
  }
  if (funcOp.getNumResults() == 0) {
    return op->emitError("'") << haloAttrName
                              << "' function must not have zero results; use "
                                 "'!prelim_hlep.linear_unit' instead";
  }

  if (!funcOp.isExternal()) {
    for (BlockArgument arg : funcOp.getArguments()) {
      // TODO: not only arguments, and not all arguments should be checked.
      // Instead, every value appearing within the function body that is not purely classical
      // should be checked. "Not purely classical" should be its own helper function,
      // and for now only checks if the type is !prelim_hlep.lin<something>
      if (failed(checkPreciselyOneUse(op, arg,
                                      "'" + haloAttrName + "' function argument #" + Twine(arg.getArgNumber())))) {
        return failure();
      }
    }
  }

  return success();
}

void PrelimHLEPDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPTypes.cpp.inc"
      >();

  addAttributes<
#define GET_ATTRDEF_LIST
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPAttrs.cpp.inc"
      >();

  addOperations<
#define GET_OP_LIST
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPOps.cpp.inc"
      >();
}
