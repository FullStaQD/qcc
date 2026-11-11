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

#include <optional>

namespace qcc::qcirc {

//===----------------------------------------------------------------------===//
// Angle operands of `qcirc` gates
//===----------------------------------------------------------------------===//

/// The value of `angle` if it is a compile-time constant, nullopt otherwise.
std::optional<double> getConstantAngle(mlir::Value angle);

/// Emits `arith.constant value : f64`.
mlir::Value buildAngle(mlir::OpBuilder& builder, mlir::Location loc, double value);

/// Returns `factor * angle`: a fresh constant if `angle` is one, an `arith.mulf` otherwise.
mlir::Value scaleAngle(mlir::OpBuilder& builder, mlir::Location loc, mlir::Value angle, double factor);

/// Returns `angle + offset`: a fresh constant if `angle` is one, an `arith.addf` otherwise.
mlir::Value offsetAngle(mlir::OpBuilder& builder, mlir::Location loc, mlir::Value angle, double offset);

} // namespace qcc::qcirc
