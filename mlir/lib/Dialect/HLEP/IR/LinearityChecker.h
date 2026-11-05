// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "qcc/Dialect/HLEP/IR/HLEP.h"

#include <mlir/Interfaces/FunctionInterfaces.h>
#include <string>

/// Linearity checks for `lin`-typed values, used by the dialect's verifiers.
namespace qcc::hlep {

/// Returns true if `type` is subject to linearity checking.
bool isNotPurelyClassical(mlir::Type type);

/// Builds a human-readable description of `value` (a linearity-checked
/// function argument, block argument, or op result) for use in diagnostics.
std::string describeLinearValue(mlir::FunctionOpInterface funcOp, mlir::Value value);

/// Tries to prove that `value` is used exactly once on every control-flow
/// path. Fails if it cannot be proven.
mlir::LogicalResult checkLinearUse(mlir::Value value, const mlir::Twine& description);

/// Verifies that every region nested in `op` that contains a value subject to
/// linearity checking has exactly one block.
mlir::LogicalResult checkSingleBlockRegions(mlir::Operation* op, const mlir::Twine& haloAttrName);

/// Verifies that every op nested in `op` that has an operand, result, or region
/// argument subject to linearity checking implements
/// `LinearityAwareOpInterface` and passes its `verifyLinearValueHandling`.
mlir::LogicalResult checkOnlyLinearityAwareOps(mlir::Operation* op, const mlir::Twine& haloAttrName);

} // namespace qcc::hlep
