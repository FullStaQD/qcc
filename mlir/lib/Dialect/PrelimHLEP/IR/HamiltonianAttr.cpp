#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include <llvm/ADT/STLExtras.h>

using namespace mlir;
using namespace qcc::prelimhlep;

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
