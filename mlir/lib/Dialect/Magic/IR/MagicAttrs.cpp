// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/IR/Magic.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectImplementation.h" // IWYU pragma: keep

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h" // IWYU pragma: keep

#include <cstdint>
#include <utility>

using namespace mlir;
using namespace qcc::magic;

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/Magic/IR/MagicAttrs.cpp.inc"

//===----------------------------------------------------------------------===//
// Registration
//===----------------------------------------------------------------------===//

// Lives here, next to the storage classes the attribute definitions bring along.
void MagicDialect::registerAttributes() {
  addAttributes<
#define GET_ATTRDEF_LIST
#include "qcc/Dialect/Magic/IR/MagicAttrs.cpp.inc"
      >();
}

//===----------------------------------------------------------------------===//
// TrapAttr
//===----------------------------------------------------------------------===//

LogicalResult TrapAttr::verify(function_ref<InFlightDiagnostic()> emitError, int64_t capacity,
                               ArrayRef<DenseElementsAttr> couplings) {
  if (capacity < 1) {
    return emitError() << "capacity must be at least 1, got " << capacity;
  }
  if (std::cmp_not_equal(couplings.size(), capacity)) {
    return emitError() << "expected one coupling matrix per occupancy 1.." << capacity << ", got " << couplings.size();
  }

  for (auto [index, matrix] : llvm::enumerate(couplings)) {
    const int64_t numIons = static_cast<int64_t>(index) + 1;
    if (!matrix) {
      return emitError() << "coupling matrix for " << numIons << " ions is missing";
    }

    const ShapedType type = matrix.getType();
    if (!type.getElementType().isF64() || type.getRank() != 2 || type.getDimSize(0) != numIons ||
        type.getDimSize(1) != numIons) {
      return emitError() << "coupling matrix for " << numIons << " ions must have type tensor<" << numIons << "x"
                         << numIons << "xf64>, got " << type;
    }

    const SmallVector<double> values(matrix.getValues<double>());
    for (int64_t i = 0; i < numIons; ++i) {
      if (values[(i * numIons) + i] != 0.0) {
        return emitError() << "coupling matrix for " << numIons << " ions must have a zero diagonal";
      }
      for (int64_t j = i + 1; j < numIons; ++j) {
        if (values[(i * numIons) + j] != values[(j * numIons) + i]) {
          return emitError() << "coupling matrix for " << numIons << " ions must be symmetric";
        }
      }
    }
  }

  return success();
}

//===----------------------------------------------------------------------===//
// DeviceAttr
//===----------------------------------------------------------------------===//

LogicalResult DeviceAttr::verify(function_ref<InFlightDiagnostic()> emitError, StringRef name, int64_t timeUnitNs,
                                 ArrayRef<int64_t> initialOccupancies, ArrayRef<TrapAttr> traps) {
  if (name.empty()) {
    return emitError() << "name must not be empty";
  }
  if (timeUnitNs <= 0) {
    return emitError() << "time_unit_ns must be positive, got " << timeUnitNs;
  }
  if (traps.empty()) {
    return emitError() << "expected at least one trap";
  }
  if (initialOccupancies.size() != traps.size()) {
    return emitError() << "expected one initial occupancy per trap, got " << initialOccupancies.size()
                       << " occupancies for " << traps.size() << " traps";
  }

  for (auto [trap, occupancy] : llvm::enumerate(initialOccupancies)) {
    if (!traps[trap]) {
      return emitError() << "trap " << trap << " is missing";
    }
    const int64_t capacity = traps[trap].getCapacity();
    if (occupancy < 0 || occupancy > capacity) {
      return emitError() << "initial occupancy of trap " << trap << " must be in 0.." << capacity << ", got "
                         << occupancy;
    }
  }

  return success();
}
