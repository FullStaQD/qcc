// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include "LinearityChecker.h"

#include <llvm/ADT/STLExtras.h>
#include <llvm/ADT/TypeSwitch.h>
#include <mlir/IR/DialectImplementation.h>
#include <mlir/Interfaces/ControlFlowInterfaces.h>
#include <mlir/Interfaces/FunctionInterfaces.h>
#include <mlir/Transforms/InliningUtils.h>
#include <utility>

using namespace mlir;
using namespace qcc::prelimhlep;

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPDialect.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPTypes.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPAttrs.cpp.inc"

#define GET_OP_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPOps.cpp.inc"

static StringRef mnemonicFor(PauliKind kind) {
  switch (kind) {
  case PauliKind::X:
    return "X";
  case PauliKind::Y:
    return "Y";
  case PauliKind::Z:
    return "Z";
  }
  llvm_unreachable("unhandled PauliKind");
}

/// Parses a single `X`/`Y`/`Z` keyword into `kind`, without erroring (and
/// without consuming input) if none is present.
static ParseResult parseOptionalPauliKind(AsmParser& parser, PauliKind& kind) {
  if (succeeded(parser.parseOptionalKeyword("X"))) {
    kind = PauliKind::X;
    return success();
  }
  if (succeeded(parser.parseOptionalKeyword("Y"))) {
    kind = PauliKind::Y;
    return success();
  }
  if (succeeded(parser.parseOptionalKeyword("Z"))) {
    kind = PauliKind::Z;
    return success();
  }
  return failure();
}

SmallVector<HamiltonianAttr::Term> HamiltonianAttr::getTerms() const {
  SmallVector<Term> terms;
  ArrayRef<PauliFactor> remaining = getFactors();
  for (const HamiltonianTermHeader& header : getTermHeaders()) {
    terms.push_back({.coefficient = header.coefficient, .factors = remaining.take_front(header.size)});
    remaining = remaining.drop_front(header.size);
  }
  return terms;
}

// Parses `qubitCount `,` term (`+` term)*`, where
// `term ::= (float `*`)? pauli-factor (`*` pauli-factor)*` and
// `pauli-factor ::= (`X`|`Y`|`Z`) `[` qubit `]`.
Attribute HamiltonianAttr::parse(AsmParser& parser, Type /*unused*/) {
  int64_t qubitCount = 0;
  if (parser.parseLess() || parser.parseInteger(qubitCount) || parser.parseComma()) {
    return {};
  }

  SmallVector<HamiltonianTermHeader> termHeaders;
  SmallVector<PauliFactor> factors;

  auto parseFactor = [&](PauliKind kind) -> ParseResult {
    int64_t qubit = 0;
    if (parser.parseLSquare() || parser.parseInteger(qubit) || parser.parseRSquare()) {
      return failure();
    }
    factors.push_back({.kind = kind, .qubit = qubit});
    return success();
  };

  auto parseTerm = [&]() -> ParseResult {
    PauliKind kind = PauliKind::X;
    double coefficient = 1.0;
    if (failed(parseOptionalPauliKind(parser, kind))) {
      bool negative = succeeded(parser.parseOptionalMinus());
      if (parser.parseFloat(coefficient)) {
        return failure();
      }
      if (negative) {
        coefficient = -coefficient;
      }
      if (parser.parseStar()) {
        return failure();
      }
      SMLoc kindLoc = parser.getCurrentLocation();
      if (failed(parseOptionalPauliKind(parser, kind))) {
        return parser.emitError(kindLoc, "expected 'X', 'Y', or 'Z'");
      }
    }

    size_t termStart = factors.size();
    if (parseFactor(kind)) {
      return failure();
    }
    while (succeeded(parser.parseOptionalStar())) {
      PauliKind nextKind = PauliKind::X;
      SMLoc kindLoc = parser.getCurrentLocation();
      if (failed(parseOptionalPauliKind(parser, nextKind))) {
        return parser.emitError(kindLoc, "expected 'X', 'Y', or 'Z'");
      }
      if (parseFactor(nextKind)) {
        return failure();
      }
    }

    termHeaders.push_back({.coefficient = coefficient, .size = static_cast<int64_t>(factors.size() - termStart)});
    return success();
  };

  if (parseTerm()) {
    return {};
  }
  while (succeeded(parser.parseOptionalPlus())) {
    if (parseTerm()) {
      return {};
    }
  }

  if (parser.parseGreater()) {
    return {};
  }

  return parser.getChecked<HamiltonianAttr>(parser.getContext(), qubitCount, termHeaders, factors);
}

void HamiltonianAttr::print(AsmPrinter& printer) const {
  printer << "<" << getQubitCount() << ", ";
  llvm::interleave(
      getTerms(), printer,
      [&](const Term& term) {
        if (term.coefficient != 1.0) {
          printer << term.coefficient << " * ";
        }
        llvm::interleave(
            term.factors, printer,
            [&](const PauliFactor& factor) { printer << mnemonicFor(factor.kind) << "[" << factor.qubit << "]"; },
            " * ");
      },
      " + ");
  printer << ">";
}

LogicalResult HamiltonianAttr::verify(function_ref<InFlightDiagnostic()> emitError, int64_t qubitCount,
                                      ArrayRef<HamiltonianTermHeader> termHeaders, ArrayRef<PauliFactor> factors) {
  if (qubitCount <= 0) {
    return emitError() << "expected a positive qubit count, got " << qubitCount;
  }
  if (termHeaders.empty()) {
    return emitError() << "expected at least one term";
  }

  SmallVector<SmallVector<PauliFactor>> normalizedTerms;
  size_t offset = 0;
  for (size_t i = 0, e = termHeaders.size(); i < e; ++i) {
    int64_t size = termHeaders[i].size;
    if (size <= 0) {
      return emitError() << "term #" << i << " must have at least one Pauli factor";
    }
    if (offset + static_cast<size_t>(size) > factors.size()) {
      return emitError() << "term sizes do not match the number of Pauli factors provided";
    }
    if (termHeaders[i].coefficient == 0.0) {
      return emitError() << "term #" << i << " has a zero coefficient";
    }

    ArrayRef<PauliFactor> termFactors = factors.slice(offset, size);
    SmallVector<PauliFactor> normalized(termFactors.begin(), termFactors.end());
    llvm::sort(normalized, [](const PauliFactor& a, const PauliFactor& b) { return a.qubit < b.qubit; });

    for (size_t j = 0, je = normalized.size(); j < je; ++j) {
      if (normalized[j].qubit < 0 || normalized[j].qubit >= qubitCount) {
        return emitError() << "term #" << i << " factor qubit index " << normalized[j].qubit
                           << " is out of range for qubit count " << qubitCount;
      }
      if (j > 0 && normalized[j].qubit == normalized[j - 1].qubit) {
        return emitError() << "term #" << i << " has more than one Pauli factor on qubit " << normalized[j].qubit;
      }
    }

    if (llvm::is_contained(normalizedTerms, normalized)) {
      return emitError() << "term #" << i << " duplicates an earlier term (up to reordering of its factors)";
    }
    normalizedTerms.push_back(std::move(normalized));

    offset += size;
  }

  return success();
}

/// Checks that `op` is nested (directly or indirectly) within a
/// `prelim_hlep.halo`-attributed function.
static LogicalResult verifyWithinHaloedFunction(Operation* op) {
  std::string haloAttrName = (PrelimHLEPDialect::getDialectNamespace() + "." + HaloAttr::getMnemonic()).str();

  auto funcOp = op->getParentOfType<FunctionOpInterface>();
  if (!funcOp || !funcOp->hasAttr(haloAttrName)) {
    return op->emitOpError("expected to be nested within a '") << haloAttrName << "'-attributed function";
  }

  return success();
}

static LogicalResult verifyInputResultTypesMatch(Operation* op, Type inputType, Type resultType) {
  if (inputType != resultType) {
    return op->emitOpError("expected result type (") << resultType << ") to match input type (" << inputType << ")";
  }
  return success();
}

LogicalResult ScaleOp::verify() {
  if (failed(verifyWithinHaloedFunction(getOperation()))) {
    return failure();
  }
  return verifyInputResultTypesMatch(getOperation(), getInput().getType(), getResult().getType());
}

LogicalResult AddPhaseOp::verify() {
  if (failed(verifyWithinHaloedFunction(getOperation()))) {
    return failure();
  }
  return verifyInputResultTypesMatch(getOperation(), getInput().getType(), getResult().getType());
}

/// Returns `N` for `iN`, `!prelim_hlep.x<N>`, or `!prelim_hlep.y<N>`.
static std::optional<int64_t> getBasisSize(Type type) {
  if (auto intType = dyn_cast<IntegerType>(type)) {
    return intType.getWidth();
  }
  if (auto xType = dyn_cast<XType>(type)) {
    return xType.getSize();
  }
  if (auto yType = dyn_cast<YType>(type)) {
    return yType.getSize();
  }
  return std::nullopt;
}

LogicalResult BaseChangeOp::verify() {
  if (failed(verifyWithinHaloedFunction(getOperation()))) {
    return failure();
  }

  auto inputType = dyn_cast<LinType>(getInput().getType());
  auto resultType = dyn_cast<LinType>(getResult().getType());
  if (!inputType || !resultType) {
    return emitOpError("expected input and result types to be '") << LinType::getMnemonic() << "' types";
  }

  std::optional<int64_t> inputSize = getBasisSize(inputType.getElementType());
  std::optional<int64_t> resultSize = getBasisSize(resultType.getElementType());
  if (!inputSize) {
    return emitOpError("expected input type's element type (")
           << inputType.getElementType() << ") to be an integer, 'x', or 'y' type";
  }
  if (!resultSize) {
    return emitOpError("expected result type's element type (")
           << resultType.getElementType() << ") to be an integer, 'x', or 'y' type";
  }
  if (*inputSize != *resultSize) {
    return emitOpError("expected input and result types to have the same qubit count, got ")
           << *inputSize << " and " << *resultSize;
  }

  return success();
}

/// A base change to the type it already has does nothing, and a base change
/// that undoes the one feeding it returns the original value.
OpFoldResult BaseChangeOp::fold(FoldAdaptor /*adaptor*/) {
  if (getInput().getType() == getResult().getType()) {
    return getInput();
  }
  if (auto producer = getInput().getDefiningOp<BaseChangeOp>()) {
    if (producer.getInput().getType() == getResult().getType()) {
      return producer.getInput();
    }
  }
  return {};
}

namespace {

/// Merges a chain of base changes into a single one:
///   base_change(base_change(%x : A -> B) : B -> C)  ->  base_change(%x : A -> C)
struct MergeBaseChangeChain final : OpRewritePattern<BaseChangeOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(BaseChangeOp op, PatternRewriter& rewriter) const override {
    auto producer = op.getInput().getDefiningOp<BaseChangeOp>();
    if (!producer) {
      return failure();
    }
    rewriter.replaceOpWithNewOp<BaseChangeOp>(op, op.getResult().getType(), producer.getInput());
    return success();
  }
};

} // namespace

void BaseChangeOp::getCanonicalizationPatterns(RewritePatternSet& results, MLIRContext* context) {
  results.add<MergeBaseChangeChain>(context);
}

// Parses `( %operand : type, ... ) (`carrying` ( %operand : type, ... ))?`.
// The `carrying (...)` group is omitted entirely when there are no
// auxiliary results, both on parse and on print.
ParseResult OutputOp::parse(OpAsmParser& parser, OperationState& result) {
  SmallVector<OpAsmParser::UnresolvedOperand> delinearizedResults;
  SmallVector<Type> delinearizedResultTypes;
  auto parseTypedOperand = [&](SmallVectorImpl<OpAsmParser::UnresolvedOperand>& operands,
                               SmallVectorImpl<Type>& types) -> ParseResult {
    return failure(parser.parseOperand(operands.emplace_back()) || parser.parseColonType(types.emplace_back()));
  };

  if (parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren, [&]() {
        return parseTypedOperand(delinearizedResults, delinearizedResultTypes);
      })) {
    return failure();
  }

  SmallVector<OpAsmParser::UnresolvedOperand> auxiliaryResults;
  SmallVector<Type> auxiliaryResultTypes;
  if (succeeded(parser.parseOptionalKeyword("carrying")) &&
      parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren,
                                     [&]() { return parseTypedOperand(auxiliaryResults, auxiliaryResultTypes); })) {
    return failure();
  }

  llvm::SMLoc loc = parser.getCurrentLocation();
  if (parser.resolveOperands(delinearizedResults, delinearizedResultTypes, loc, result.operands) ||
      parser.resolveOperands(auxiliaryResults, auxiliaryResultTypes, loc, result.operands)) {
    return failure();
  }
  result.addAttribute(OutputOp::getOperandSegmentSizesAttrName(result.name),
                      parser.getBuilder().getDenseI32ArrayAttr({static_cast<int32_t>(delinearizedResults.size()),
                                                                static_cast<int32_t>(auxiliaryResults.size())}));

  return parser.parseOptionalAttrDict(result.attributes);
}

void OutputOp::print(OpAsmPrinter& p) {
  p << " (";
  llvm::interleaveComma(getDelinearizedResults(), p, [&](Value value) { p << value << " : " << value.getType(); });
  p << ")";
  if (!getAuxiliaryResults().empty()) {
    p << " carrying (";
    llvm::interleaveComma(getAuxiliaryResults(), p, [&](Value value) { p << value << " : " << value.getType(); });
    p << ")";
  }
  p.printOptionalAttrDict((*this)->getAttrs(), {OutputOp::getOperandSegmentSizesAttrName((*this)->getName())});
}

LogicalResult OutputOp::verify() { return verifyWithinHaloedFunction(getOperation()); }

OpFoldResult ConstantOp::fold(FoldAdaptor /*adaptor*/) { return getValueAttr(); }

LogicalResult ConstantOp::verify() {
  Type resultType = getResult().getType();
  StringRef value = getValue();

  if (auto xType = dyn_cast<XType>(resultType)) {
    if (static_cast<int64_t>(value.size()) != xType.getSize()) {
      return emitOpError("expected a length-")
             << xType.getSize() << " string for result type " << resultType << ", got length " << value.size();
    }
    for (char c : value) {
      if (c != '+' && c != '-') {
        return emitOpError("expected only '+'/'-' symbols for result type ") << resultType << ", got '" << c << "'";
      }
    }
    return success();
  }

  // From ODS we already know that the result type is either `XType` or `YType`, so the cast is safe.
  auto yType = cast<YType>(resultType);
  if (static_cast<int64_t>(value.size()) != 2 * yType.getSize()) {
    return emitOpError("expected a length-")
           << (2 * yType.getSize()) << " string (" << yType.getSize() << " '->'/'<-' symbols) for result type "
           << resultType << ", got length " << value.size();
  }
  for (size_t i = 0, e = value.size(); i < e; i += 2) {
    StringRef symbol = value.substr(i, 2);
    if (symbol != "->" && symbol != "<-") {
      return emitOpError("expected only '->'/'<-' symbols for result type ")
             << resultType << ", got '" << symbol << "'";
    }
  }
  return success();
}

LogicalResult ExpOp::verify() {
  if (failed(verifyWithinHaloedFunction(getOperation()))) {
    return failure();
  }

  if (failed(verifyInputResultTypesMatch(getOperation(), getInput().getType(), getResult().getType()))) {
    return failure();
  }

  auto inputType = dyn_cast<LinType>(getInput().getType());
  IntegerType elementType = inputType ? dyn_cast<IntegerType>(inputType.getElementType()) : nullptr;
  if (!elementType) {
    return emitOpError("expected input/result types to be purely-quantum '")
           << LinType::getMnemonic() << "<i<n>>' types, got " << getInput().getType();
  }

  int64_t qubitCount = getHamiltonian().getQubitCount();
  if (std::cmp_not_equal(qubitCount, elementType.getWidth())) {
    return emitOpError("expected hamiltonian qubit count (")
           << qubitCount << ") to match input/result bit width (" << elementType.getWidth() << ")";
  }

  return success();
}

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

/// Whether `value`, defined in or captured by `body`, may depend on one of
/// `body`'s delinearized block arguments. The results of an op with regions
/// are assumed to depend on everything its regions capture.
static bool mayDependOnDelinearized(Region& body, Value value) {
  SmallVector<Value> worklist{value};
  DenseSet<Value> visited;
  while (!worklist.empty()) {
    Value current = worklist.pop_back_val();
    if (!visited.insert(current).second || !body.isAncestor(current.getParentRegion())) {
      continue;
    }
    // Only block arguments of `body` itself are reachable: values defined in
    // nested regions are never pushed below.
    Operation* def = current.getDefiningOp();
    if (def == nullptr) {
      return true;
    }
    def->walk([&](Operation* nested) {
      for (Value operand : nested->getOperands()) {
        if (!def->isAncestor(operand.getParentRegion()->getParentOp())) {
          worklist.push_back(operand);
        }
      }
    });
  }
  return false;
}

/// Whether `body` uses a linear value defined outside of it.
static bool capturesLinearValue(Region& body) {
  WalkResult result = body.walk([&](Operation* op) {
    for (Value operand : op->getOperands()) {
      if (isa<LinType>(operand.getType()) && !body.isAncestor(operand.getParentRegion())) {
        return WalkResult::interrupt();
      }
    }
    return WalkResult::advance();
  });
  return result.wasInterrupted();
}

// TODO: Understand better and revisit.
// The body's own effects are added by `RecursiveMemoryEffects`; see the op
// description for the effects of the op itself.
void LinOp::getEffects(SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>>& effects) {
  Region& body = getBody();

  // A classical `carrying` result that depends on a delinearized value is a
  // measurement outcome: the op has several worlds. Linear `carrying`
  // results (e.g. the target of a controlled gate) and units do not branch.
  auto output = dyn_cast<OutputOp>(body.front().getTerminator());
  bool branchesWorlds = !output || llvm::any_of(output.getAuxiliaryResults(), [&](Value aux) {
    return !isa<LinType, UnitType>(aux.getType()) && mayDependOnDelinearized(body, aux);
  });
  if (branchesWorlds) {
    effects.emplace_back(MemoryEffects::Read::get(), WorldResource::get());
    effects.emplace_back(MemoryEffects::Write::get(), WorldResource::get());
  }

  bool capturesLinear = capturesLinearValue(body);
  bool consumesLinear = !getDelinearizedOperands().empty() || capturesLinear;
  bool producesLinear = llvm::any_of(getResultTypes(), [](Type type) { return isa<LinType>(type); });

  // Linear results out of nothing: two such ops must not be merged.
  if (!consumesLinear) {
    for (OpResult result : getResults()) {
      if (isa<LinType>(result.getType())) {
        effects.emplace_back(MemoryEffects::Allocate::get(), result, QuantumStateResource::get());
      }
    }
  }

  // Linear values into nothing: the op must not be erased as dead.
  if (consumesLinear && !producesLinear) {
    for (OpOperand& operand : getDelinearizedOperandsMutable()) {
      effects.emplace_back(MemoryEffects::Free::get(), &operand, QuantumStateResource::get());
    }
    if (capturesLinear) {
      effects.emplace_back(MemoryEffects::Free::get(), QuantumStateResource::get());
    }
  }
}

Operation* PrelimHLEPDialect::materializeConstant(OpBuilder& builder, Attribute value, Type type, Location loc) {
  auto stringValue = dyn_cast<StringAttr>(value);
  if (!stringValue || !isa<XType, YType>(type)) {
    return nullptr;
  }
  return ConstantOp::create(builder, loc, type, stringValue);
}

/// Verifier for function-like operations latched on via `prelim_hlep.halo` attribute.
/// Checks that the function has at least one argument and one result,
/// and that all values subject to linearity within the function are provably used exactly once.
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
                                 "'!prelim_hlep.unit' instead";
  }
  if (funcOp.getNumResults() == 0) {
    return op->emitError("'") << haloAttrName
                              << "' function must not have zero results; use "
                                 "'!prelim_hlep.unit' instead";
  }

  if (!funcOp.isExternal()) {
    if (failed(checkSingleBlockRegions(op, haloAttrName))) {
      return failure();
    }
    if (failed(checkNoSelectOfLinearValues(op, haloAttrName))) {
      return failure();
    }

    LogicalResult result = success();
    op->walk([&](Operation* nestedOp) {
      for (Region& region : nestedOp->getRegions()) {
        for (Block& block : region) {
          for (BlockArgument arg : block.getArguments()) {
            if (isNotPurelyClassical(arg.getType()) &&
                failed(checkPreciselyOneUse(arg, "'" + haloAttrName + "' " + describeLinearValue(funcOp, arg)))) {
              result = failure();
            }
          }
        }
      }
      for (OpResult opResult : nestedOp->getResults()) {
        if (isNotPurelyClassical(opResult.getType()) &&
            failed(checkPreciselyOneUse(opResult, "'" + haloAttrName + "' " + describeLinearValue(funcOp, opResult)))) {
          result = failure();
        }
      }
    });
    if (failed(result)) {
      return failure();
    }
  }

  return success();
}

namespace {
/// Inliner interface for the PrelimHLEP dialect. All PrelimHLEP ops are
/// cloneable and may be inlined into any haloed context (in particular into
/// `prelim_hlep.lin` bodies), but not into non-haloed functions: that would
/// strip the linear context the ops' verifiers and the linearity checker
/// rely on. Since the inliner only inlines a call if every op of the
/// callee may move, this also keeps haloed callees out of non-haloed
/// callers.
struct PrelimHLEPInlinerInterface final : DialectInlinerInterface {
  using DialectInlinerInterface::DialectInlinerInterface;

  bool isLegalToInline(Region* /*dest*/, Region* /*src*/, bool /*wouldBeCloned*/,
                       IRMapping& /*valueMapping*/) const override {
    /// This overload is used for coarse checking, i.e.: Can this kind of region be inlined at all?
    return true;
  }

  bool isLegalToInline(Operation* /*op*/, Region* dest, bool /*wouldBeCloned*/,
                       IRMapping& /*valueMapping*/) const override {
    std::string haloAttrName = (PrelimHLEPDialect::getDialectNamespace() + "." + HaloAttr::getMnemonic()).str();
    Operation* parent = dest->getParentOp();
    while (parent != nullptr && !isa<FunctionOpInterface>(parent)) {
      parent = parent->getParentOp();
    }
    return parent != nullptr && parent->hasAttr(haloAttrName);
  }
};
} // namespace

void PrelimHLEPDialect::initialize() {
  addInterfaces<PrelimHLEPInlinerInterface>();

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
