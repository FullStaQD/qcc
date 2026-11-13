// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QCirc/Transforms/Angles.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/Value.h"

#include <optional>

using namespace mlir;

std::optional<double> qcc::qcirc::getConstantAngle(Value angle) {
  FloatAttr attr;
  if (!matchPattern(angle, m_Constant(&attr))) {
    return std::nullopt;
  }
  return attr.getValueAsDouble();
}

Value qcc::qcirc::buildAngle(OpBuilder& builder, Location loc, double value) {
  return arith::ConstantOp::create(builder, loc, builder.getF64FloatAttr(value));
}

Value qcc::qcirc::scaleAngle(OpBuilder& builder, Location loc, Value angle, double factor) {
  if (std::optional<double> value = getConstantAngle(angle)) {
    return buildAngle(builder, loc, *value * factor);
  }
  return arith::MulFOp::create(builder, loc, angle, buildAngle(builder, loc, factor));
}

Value qcc::qcirc::offsetAngle(OpBuilder& builder, Location loc, Value angle, double offset) {
  if (std::optional<double> value = getConstantAngle(angle)) {
    return buildAngle(builder, loc, *value + offset);
  }
  return arith::AddFOp::create(builder, loc, angle, buildAngle(builder, loc, offset));
}
