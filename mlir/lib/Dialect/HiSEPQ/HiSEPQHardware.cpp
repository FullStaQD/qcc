// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/HiSEPQ/HiSEPQHardware.h"

#include "mlir/Dialect/DLTI/DLTI.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Support/LogicalResult.h"

#include <optional>

using namespace mlir;

namespace qcc::hisepq {

Hardware Hardware::fromModule(ModuleOp moduleOp) {
  Hardware hardware;

  auto targetAttr = moduleOp->getAttrOfType<MapAttr>(targetAttrName);
  if (!targetAttr) {
    return hardware;
  }

  FailureOr<Attribute> minVLen = targetAttr.query(StringAttr::get(moduleOp.getContext(), minVLenKey));
  if (failed(minVLen)) {
    return hardware;
  }

  // Well-formedness is `HiSEPQDialect::verifyOperationAttribute`'s job, and the module has verified
  // by the time any pass runs.
  hardware.minVLen = static_cast<unsigned>(cast<IntegerAttr>(*minVLen).getValue().getZExtValue());
  return hardware;
}

std::optional<VectorType> Hardware::qubitVectorType(MLIRContext* ctx, unsigned numQubits) const {
  for (unsigned knownMinElements : supportedKnownMinElements) {
    if (elementsFor(knownMinElements) >= numQubits) {
      return VectorType::get({knownMinElements}, IntegerType::get(ctx, 8), /*scalableDims=*/{true});
    }
  }

  return std::nullopt;
}

} // namespace qcc::hisepq
