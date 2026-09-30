// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/IR/Builders.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Value.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>

namespace qcc::qvec {

//===----------------------------------------------------------------------===//
// Angle operands of `qvec` gates
//===----------------------------------------------------------------------===//

/// The elements (row-major) of `angles` if it is a compile-time constant, nullopt otherwise. Besides `arith.constant`
/// this looks through `vector.from_elements` and `vector.broadcast` of constant scalars.
std::optional<llvm::SmallVector<double>> getConstantAngles(mlir::Value angles);

/// Emits `arith.constant dense<values> : vector<Nxf64>`, N = `values.size()`.
mlir::Value buildAngleVector(mlir::OpBuilder& builder, mlir::Location loc, llvm::ArrayRef<double> values);

/// Emits the splat `arith.constant dense<value> : vector<widthxf64>` from a single `value`.
mlir::Value buildSplatAngleVector(mlir::OpBuilder& builder, mlir::Location loc, int64_t width, double value);

/// Emits `arith.constant dense<...> : vector<NxNxf64>` from the row-major `values`, N = `width`.
mlir::Value buildAngleMatrix(mlir::OpBuilder& builder, mlir::Location loc, int64_t width,
                             llvm::ArrayRef<double> values);

/// Returns `factor * angles`: a fresh constant if `angles` is one, an `arith.mulf` by a splat constant otherwise.
mlir::Value scaleAngles(mlir::OpBuilder& builder, mlir::Location loc, mlir::Value angles, double factor);

} // namespace qcc::qvec
