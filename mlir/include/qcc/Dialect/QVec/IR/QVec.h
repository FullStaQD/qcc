// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/Dialect/QCO/IR/QCODialect.h" // IWYU pragma: keep
#include "mlir/Dialect/QCO/IR/QCOOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"

#include <cassert>
#include <cstdint>

//===----------------------------------------------------------------------===//
// QVec Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVecDialect.h.inc"

//===----------------------------------------------------------------------===//
// QVec Attributes
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVecEnums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/QVec/IR/QVecAttrs.h.inc"

//===----------------------------------------------------------------------===//
// QVec type predicates
//===----------------------------------------------------------------------===//

namespace qcc::qvec {

/// Whether `type` is a vector with element type `!qco.qubit`.
inline bool isQubitVector(mlir::Type type) {
  auto vectorType = mlir::dyn_cast<mlir::VectorType>(type);
  return vectorType && mlir::isa<mlir::qco::QubitType>(vectorType.getElementType());
}

/// Positions of the three parameters of `qvec.single u_zxz(z1, x, z2)` = Rz(z2) * Rx(x) * Rz(z1), z1 applied first.
namespace zxz {
inline constexpr unsigned z1 = 0;
inline constexpr unsigned x = 1;
inline constexpr unsigned z2 = 2;
} // namespace zxz

} // namespace qcc::qvec

//===----------------------------------------------------------------------===//
// QVec Interfaces
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVecInterfaces.h.inc"

//===----------------------------------------------------------------------===//
// QVec Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/QVec/IR/QVecOps.h.inc"

namespace qcc::qvec {

/// Traces back the qubit at `index` in the vector `qubits` to a StaticOp and returns it if possible (null value if
/// not).
mlir::qco::StaticOp getStaticOpAncestor(mlir::TypedValue<mlir::VectorType> qubits, int64_t index);

} // namespace qcc::qvec
