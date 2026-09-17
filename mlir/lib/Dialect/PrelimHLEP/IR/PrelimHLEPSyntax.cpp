//===----------------------------------------------------------------------===//
//
// Custom assembly syntax for the PrelimHLEP dialect: the hand-written
// parsers and printers of 'prelimhlep.lin', 'prelimhlep.output' and
// '#prelimhlep.hamiltonian'.
//
// This file defines the textual exchange format between qcc and the Mojo
// fork, and is shared verbatim with it (see 'mojo/dialect-sync/MANIFEST').
// Keep it free of anything the fork does not have: only the stable
// 'OpAsmParser'/'OpAsmPrinter'/'AsmParser'/'AsmPrinter' API, and no
// dependency on qcc-only code such as the verifiers or 'LinShapes.h'.
//
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include <llvm/ADT/STLExtras.h>
#include <mlir/IR/DialectImplementation.h>

using namespace mlir;
using namespace qcc::prelimhlep;

//===----------------------------------------------------------------------===//
// HamiltonianAttr
//===----------------------------------------------------------------------===//

namespace {
StringRef mnemonicFor(PauliKind kind) {
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
ParseResult parseOptionalPauliKind(AsmParser& parser, PauliKind& kind) {
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
} // namespace

SmallVector<HamiltonianAttr::Term> HamiltonianAttr::getTerms() const {
  SmallVector<Term> terms;
  ArrayRef<PauliFactor> remaining = getFactors();
  for (const HamiltonianTermHeader& header : getTermHeaders()) {
    terms.push_back({header.coefficient, remaining.take_front(header.size)});
    remaining = remaining.drop_front(header.size);
  }
  return terms;
}

// Parses `qubitCount `,` term (`+` term)*`, where
// `term ::= (float `*`)? pauli-factor (`*` pauli-factor)*` and
// `pauli-factor ::= (`X`|`Y`|`Z`) `[` qubit `]`.
Attribute HamiltonianAttr::parse(AsmParser& parser, Type) {
  SMLoc attrLoc = parser.getCurrentLocation();

  int64_t qubitCount;
  if (parser.parseLess() || parser.parseInteger(qubitCount) || parser.parseComma()) {
    return {};
  }

  SmallVector<HamiltonianTermHeader> termHeaders;
  SmallVector<PauliFactor> factors;

  auto parseFactor = [&](PauliKind kind) -> ParseResult {
    int64_t qubit;
    if (parser.parseLSquare() || parser.parseInteger(qubit) || parser.parseRSquare()) {
      return failure();
    }
    factors.push_back({kind, qubit});
    return success();
  };

  auto parseTerm = [&]() -> ParseResult {
    PauliKind kind;
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
      PauliKind nextKind;
      SMLoc kindLoc = parser.getCurrentLocation();
      if (failed(parseOptionalPauliKind(parser, nextKind))) {
        return parser.emitError(kindLoc, "expected 'X', 'Y', or 'Z'");
      }
      if (parseFactor(nextKind)) {
        return failure();
      }
    }

    termHeaders.push_back({coefficient, static_cast<int64_t>(factors.size() - termStart)});
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

  // Spelled with exactly the generated overload's parameter types: an inexact call would instead pick up the
  // inherited 'Base::getChecked' template, which needs the storage class defined in 'PrelimHLEPDialect.cpp'.
  auto emitError = [&]() { return parser.emitError(attrLoc); };
  return HamiltonianAttr::getChecked(function_ref<InFlightDiagnostic()>(emitError), parser.getContext(), qubitCount,
                                     ArrayRef<HamiltonianTermHeader>(termHeaders), ArrayRef<PauliFactor>(factors));
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

//===----------------------------------------------------------------------===//
// OutputOp
//===----------------------------------------------------------------------===//

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

//===----------------------------------------------------------------------===//
// LinOp
//===----------------------------------------------------------------------===//

// Parses `shape? ( %arg : argType from %operand : operandType, ... ) -> ( resultType, ... ) region`,
// where the optional leading `shape` is a bare `LinShape` keyword.
ParseResult LinOp::parse(OpAsmParser& parser, OperationState& result) {
  StringRef shapeKeyword;
  if (succeeded(parser.parseOptionalKeyword(&shapeKeyword))) {
    std::optional<LinShape> shape = symbolizeLinShape(shapeKeyword);
    if (!shape) {
      return parser.emitError(parser.getCurrentLocation(), "unknown 'prelimhlep.lin' shape '") << shapeKeyword << "'";
    }
    result.addAttribute(getShapeAttrName(result.name), LinShapeAttr::get(parser.getContext(), *shape));
  }

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
  if (std::optional<LinShape> shape = getShape()) {
    p << " " << stringifyLinShape(*shape);
  }
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
  p.printOptionalAttrDict((*this)->getAttrs(), {getShapeAttrName()});
}
