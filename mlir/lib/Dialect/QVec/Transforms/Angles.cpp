// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/Transforms/Angles.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cassert>
#include <cstdint>
#include <optional>

using namespace mlir;

/// The `f64` element type of every angle vector.
static Type getAngleType(OpBuilder& builder) { return Float64Type::get(builder.getContext()); }

/// The value of `scalar` if it is a constant f64.
static std::optional<double> getConstantAngle(Value scalar) {
  FloatAttr attr;
  if (!matchPattern(scalar, m_Constant(&attr))) {
    return std::nullopt;
  }
  return attr.getValueAsDouble();
}

std::optional<SmallVector<double>> qcc::qvec::getConstantAngles(Value angles) {
  auto vectorType = cast<VectorType>(angles.getType());
  const int64_t numElements = vectorType.getNumElements();

  DenseFPElementsAttr dense;
  if (matchPattern(angles, m_Constant(&dense))) {
    return llvm::to_vector(dense.getValues<double>());
  }

  if (auto fromElementsOp = angles.getDefiningOp<vector::FromElementsOp>()) {
    SmallVector<double> values;
    for (Value element : fromElementsOp.getElements()) {
      std::optional<double> value = getConstantAngle(element);
      if (!value) {
        return std::nullopt;
      }
      values.push_back(*value);
    }
    return values;
  }

  if (auto broadcastOp = angles.getDefiningOp<vector::BroadcastOp>()) {
    Value scalar = broadcastOp.getSource();
    if (!isa<VectorType>(scalar.getType())) {
      if (std::optional<double> value = getConstantAngle(scalar)) {
        return SmallVector<double>(static_cast<size_t>(numElements), *value);
      }
    }
  }
  return std::nullopt;
}

Value qcc::qvec::buildAngleVector(OpBuilder& builder, Location loc, ArrayRef<double> values) {
  auto type = VectorType::get({static_cast<int64_t>(values.size())}, getAngleType(builder));
  return arith::ConstantOp::create(builder, loc, DenseFPElementsAttr::get(type, values));
}

Value qcc::qvec::buildSplatAngleVector(OpBuilder& builder, Location loc, int64_t width, double value) {
  auto type = VectorType::get({width}, getAngleType(builder));
  return arith::ConstantOp::create(builder, loc, DenseFPElementsAttr::get(type, value));
}

Value qcc::qvec::buildAngleMatrix(OpBuilder& builder, Location loc, int64_t width, ArrayRef<double> values) {
  assert(static_cast<int64_t>(values.size()) == width * width && "matrix values do not match the width");
  auto type = VectorType::get({width, width}, getAngleType(builder));
  return arith::ConstantOp::create(builder, loc, DenseFPElementsAttr::get(type, values));
}

Value qcc::qvec::scaleAngles(OpBuilder& builder, Location loc, Value angles, double factor) {
  if (std::optional<SmallVector<double>> values = getConstantAngles(angles)) {
    for (double& value : *values) {
      value *= factor;
    }
    return buildAngleVector(builder, loc, *values);
  }
  const int64_t width = cast<VectorType>(angles.getType()).getNumElements();
  return arith::MulFOp::create(builder, loc, angles, buildSplatAngleVector(builder, loc, width, factor));
}
