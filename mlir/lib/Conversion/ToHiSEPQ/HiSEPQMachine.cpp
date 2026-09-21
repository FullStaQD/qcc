// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/ToHiSEPQ/HiSEPQMachine.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"

#include "llvm/Support/MathExtras.h"

#include <cassert>
#include <cstdint>
#include <optional>

using namespace mlir;

namespace qcc::hisepq {

HiSEPQMachine::HiSEPQMachine(unsigned minVLen, unsigned qubitElementWidth)
    : minVLen(minVLen), qubitElementWidth(qubitElementWidth) {
  assert(isSupportedMinVLen(minVLen) && "min VLEN has to be validated by the caller");
  assert(isSupportedQubitElementWidth(qubitElementWidth) && "QEW has to be validated by the caller");
}

bool HiSEPQMachine::isSupportedMinVLen(unsigned minVLen) {
  return minVLen >= rvvBitsPerBlock && llvm::isPowerOf2_32(minVLen);
}

bool HiSEPQMachine::isSupportedQubitElementWidth(unsigned qubitElementWidth) {
  // 8 and 16 are the only safe values for our currently hardcoded set of LMUL values; `knownMinElementsFor` asserts
  // on anything wider.
  return qubitElementWidth == 8 || qubitElementWidth == 16;
}

unsigned HiSEPQMachine::knownMinElementsFor(unsigned lmul8) const {
  const unsigned knownMinElements = (lmul8 * rvvBitsPerBlock) / (8 * qubitElementWidth);

  // Could fail for e.g. mf4 and QEW=32, or mf8 and QEW=16:
  assert(knownMinElements >= 1 && "LMUL too narrow for this QEW");
  return knownMinElements;
}

unsigned HiSEPQMachine::maxQubits() const { return vscale() * knownMinElementsFor(supportedLMul8.back()); }

uint64_t HiSEPQMachine::maxQubitIndex() const { return (uint64_t{1} << qubitElementWidth) - 1; }

std::optional<VectorType> HiSEPQMachine::qubitVectorType(MLIRContext* ctx, unsigned numQubits) const {
  for (unsigned lmul8 : supportedLMul8) {
    const unsigned knownMinElements = knownMinElementsFor(lmul8);
    if (vscale() * knownMinElements >= numQubits) {
      return VectorType::get({knownMinElements}, IntegerType::get(ctx, qubitElementWidth),
                             /*scalableDims=*/{true});
    }
  }

  return std::nullopt;
}

} // namespace qcc::hisepq
