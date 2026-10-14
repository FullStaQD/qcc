// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/OQ3/IR/OQ3.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"

#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/CheckedArithmetic.h"

#include <cstdint>
#include <numbers>
#include <optional>

using namespace mlir;
using namespace qcc;
using namespace qcc::oq3;

namespace {

/// Evaluates const expressions over `oq3` operations.
class ConstantEvaluator {
public:
  explicit ConstantEvaluator(function_ref<InFlightDiagnostic(Operation*)> emitError) : emitError(emitError) {}

  FailureOr<ConstantValue> evaluate(Value value) {
    Operation* op = value.getDefiningOp();
    if (!op) {
      return fail(nullptr, "not a constant expression");
    }
    return TypeSwitch<Operation*, FailureOr<ConstantValue>>(op)
        .Case([&](ConstantOp constant) { return evaluateLiteral(constant); })
        .Case([&](MathConstantOp constant) { return evaluateMathConstant(constant); })
        .Case([&](UnaryOp unary) { return evaluateUnary(unary); })
        .Case([&](BinaryOp binary) { return evaluateBinary(binary); })
        .Case([&](CastOp cast) { return evaluateCast(cast); })
        .Default([&](Operation* other) { return fail(other, "not a constant expression"); });
  }

private:
  FailureOr<ConstantValue> fail(Operation* op, const Twine& message) {
    if (emitError && op) {
      emitError(op) << message;
    }
    return failure();
  }

  FailureOr<ConstantValue> evaluateLiteral(ConstantOp constant) {
    if (auto literal = dyn_cast<IntLiteralAttr>(constant.getValue())) {
      const APInt& value = literal.getValue();
      if (value.getActiveBits() > 63) {
        return fail(constant, "integer literal is too large for a constant expression");
      }
      return ConstantValue::getInt(static_cast<int64_t>(value.getZExtValue()));
    }
    if (auto literal = dyn_cast<FloatLiteralAttr>(constant.getValue())) {
      double value = 0.0;
      if (literal.getText().getAsDouble(value, /*AllowInexact=*/true)) {
        return fail(constant, "invalid floating-point literal");
      }
      return ConstantValue::getFloat(value);
    }
    return fail(constant, "not a numeric constant");
  }

  static FailureOr<ConstantValue> evaluateMathConstant(MathConstantOp constant) {
    switch (constant.getKind()) {
    case MathConstantKind::Pi:
      return ConstantValue::getFloat(std::numbers::pi);
    case MathConstantKind::Tau:
      return ConstantValue::getFloat(2 * std::numbers::pi);
    case MathConstantKind::Euler:
      return ConstantValue::getFloat(std::numbers::e);
    }
    llvm_unreachable("unknown math constant");
  }

  FailureOr<ConstantValue> evaluateUnary(UnaryOp unary) {
    FailureOr<ConstantValue> operand = evaluate(unary.getOperand());
    if (failed(operand)) {
      return failure();
    }
    if (!operand->isInt()) {
      return ConstantValue::getFloat(-operand->floatValue);
    }
    const std::optional<int64_t> negated = llvm::checkedSub(int64_t{0}, operand->intValue);
    if (!negated) {
      return fail(unary, "overflow in a constant expression");
    }
    return ConstantValue::getInt(*negated);
  }

  FailureOr<ConstantValue> evaluateBinary(BinaryOp binary) {
    if (!isa<UnsizedIntType, UnsizedFloatType>(binary.getType())) {
      return fail(binary, "not a numeric constant expression");
    }
    FailureOr<ConstantValue> lhs = evaluate(binary.getLhs());
    FailureOr<ConstantValue> rhs = evaluate(binary.getRhs());
    if (failed(lhs) || failed(rhs)) {
      return failure();
    }

    if (lhs->isInt() && rhs->isInt()) {
      const int64_t a = lhs->intValue;
      const int64_t b = rhs->intValue;
      std::optional<int64_t> result;
      switch (binary.getKind()) {
      case BinaryKind::Add:
        result = llvm::checkedAdd(a, b);
        break;
      case BinaryKind::Sub:
        result = llvm::checkedSub(a, b);
        break;
      case BinaryKind::Mul:
        result = llvm::checkedMul(a, b);
        break;
      case BinaryKind::Div:
        if (b == 0) {
          return fail(binary, "division by zero in a constant expression");
        }
        if (a == INT64_MIN && b == -1) {
          break;
        }
        result = a / b;
        break;
      }
      if (!result) {
        return fail(binary, "overflow in a constant expression");
      }
      return ConstantValue::getInt(*result);
    }

    // Operands of a float operation are floats (the importer casts them).
    const double a = lhs->isInt() ? static_cast<double>(lhs->intValue) : lhs->floatValue;
    const double b = rhs->isInt() ? static_cast<double>(rhs->intValue) : rhs->floatValue;
    switch (binary.getKind()) {
    case BinaryKind::Add:
      return ConstantValue::getFloat(a + b);
    case BinaryKind::Sub:
      return ConstantValue::getFloat(a - b);
    case BinaryKind::Mul:
      return ConstantValue::getFloat(a * b);
    case BinaryKind::Div:
      return ConstantValue::getFloat(a / b);
    }
    llvm_unreachable("unknown binary operator");
  }

  FailureOr<ConstantValue> evaluateCast(CastOp cast) {
    FailureOr<ConstantValue> input = evaluate(cast.getInput());
    if (failed(input)) {
      return failure();
    }
    if (isa<UnsizedFloatType>(cast.getType()) && input->isInt()) {
      return ConstantValue::getFloat(static_cast<double>(input->intValue));
    }
    return fail(cast, "not a numeric constant expression");
  }

  function_ref<InFlightDiagnostic(Operation*)> emitError;
};

} // namespace

FailureOr<ConstantValue> qcc::oq3::evaluateConstant(Value value,
                                                    function_ref<InFlightDiagnostic(Operation*)> emitError) {
  return ConstantEvaluator(emitError).evaluate(value);
}

FailureOr<int64_t> qcc::oq3::evaluateConstantInt(Value value, function_ref<InFlightDiagnostic(Operation*)> emitError) {
  FailureOr<ConstantValue> result = evaluateConstant(value, emitError);
  if (failed(result)) {
    return failure();
  }
  if (!result->isInt()) {
    if (emitError && value.getDefiningOp()) {
      emitError(value.getDefiningOp()) << "not an integer constant expression";
    }
    return failure();
  }
  return result->intValue;
}
