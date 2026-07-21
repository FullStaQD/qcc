#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include <llvm/ADT/STLExtras.h>
#include <mlir/IR/DialectImplementation.h>

using namespace mlir;
using namespace qcc::prelimhlep;

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
