// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "qcc/Dialect/Qcc/IR/Qcc.h" // IWYU pragma: keep

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Value.h"

#include <cassert>
#include <cstdint>
#include <optional>

//===----------------------------------------------------------------------===//
// QVec Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/IR/QVecDialect.h.inc"

//===----------------------------------------------------------------------===//
// QVec Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/QVec/IR/QVecOps.h.inc"

namespace qcc::qvec {

/// Traces back the qubit at `index` in the vector `qubits` to its `qcc.static` and returns its static index, or nullopt
/// if that fails.
std::optional<int64_t> getStaticQubitIndex(mlir::TypedValue<mlir::VectorType> qubits, int64_t index);

} // namespace qcc::qvec
