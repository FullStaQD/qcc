// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/PrelimHLEP/IR/LinBitEvaluator.h"

#include <mlir/Dialect/Arith/IR/Arith.h>
#include <mlir/Dialect/Func/IR/FuncOps.h>
#include <mlir/IR/Matchers.h>

using namespace mlir;
using namespace qcc::prelimhlep;

//===----------------------------------------------------------------------===//
// LinBitEvaluator
//===----------------------------------------------------------------------===//

LinBitEvaluator::LinBitEvaluator(LinOp op) : op(op) {
  Block& body = op.getBody().front();
  for (auto [index, arg] : llvm::enumerate(body.getArguments())) {
    auto intType = dyn_cast<IntegerType>(arg.getType());
    if (!intType) {
      valid = false;
      return;
    }
    Bits bits;
    for (unsigned j = 0; j < intType.getWidth(); ++j) {
      bits.push_back(BitValue::makeInput(numInputBits + j, false));
      origins.emplace_back(index, j);
    }
    numInputBits += intType.getWidth();
    cache[arg] = std::move(bits);
  }
}

std::optional<Bits> LinBitEvaluator::fail(Operation* failed, const Twine& message) {
  if (!failureOp) {
    failureOp = failed;
    failureMessage = message.str();
  }
  return std::nullopt;
}

std::optional<Bits> LinBitEvaluator::evaluate(Value value) {
  if (auto it = cache.find(value); it != cache.end()) {
    return it->second;
  }

  // Integers, and the classical X-/Y-basis types, whose symbols are bits
  // (`+`/`->` are 0, `-`/`<-` are 1).
  unsigned width = 0;
  if (auto intType = dyn_cast<IntegerType>(value.getType())) {
    width = intType.getWidth();
  } else if (auto xType = dyn_cast<XType>(value.getType())) {
    width = xType.getSize();
  } else if (auto yType = dyn_cast<YType>(value.getType())) {
    width = yType.getSize();
  } else {
    return fail(op, "cannot interpret non-integer value");
  }
  if (width > 64) {
    return fail(op, "cannot interpret non-integer value");
  }

  APInt constant;
  if (matchPattern(value, m_ConstantInt(&constant))) {
    Bits bits;
    for (unsigned j = 0; j < width; ++j) {
      bits.push_back(BitValue::makeConstant(constant[j]));
    }
    cache[value] = bits;
    return bits;
  }

  Operation* def = value.getDefiningOp();
  if (!def) {
    return fail(op, "value is not derived from the delinearized inputs");
  }

  std::optional<Bits> result;
  if (auto basisConstant = dyn_cast<ConstantOp>(def)) {
    bool isY = isa<YType>(basisConstant.getType());
    StringRef symbols = basisConstant.getValue();
    Bits bits;
    while (!symbols.empty()) {
      bits.push_back(BitValue::makeConstant(isY ? symbols.starts_with("<-") : symbols.front() == '-'));
      symbols = symbols.drop_front(isY ? 2 : 1);
    }
    result = bits;
  } else if (auto select = dyn_cast<arith::SelectOp>(def)) {
    // A choice between two values that agree or differ by constants, e.g.
    // between the two symbols of a basis.
    std::optional<Bits> cond = evaluate(select.getCondition());
    std::optional<Bits> lhs = evaluate(select.getTrueValue());
    std::optional<Bits> rhs = evaluate(select.getFalseValue());
    if (cond && lhs && rhs) {
      BitValue c = cond->front();
      Bits bits;
      for (unsigned j = 0; j < width; ++j) {
        BitValue l = (*lhs)[j];
        BitValue r = (*rhs)[j];
        if (c.isConstant()) {
          bits.push_back(c.flag ? l : r);
        } else if (l == r) {
          bits.push_back(l);
        } else if (l.isConstant() && r.isConstant()) {
          // The condition or its negation.
          bits.push_back(BitValue::makeInput(c.input, c.flag == l.flag));
        } else {
          return fail(def, "'select' of non-constant values");
        }
      }
      result = bits;
    }
  } else if (auto ext = dyn_cast<arith::ExtUIOp>(def)) {
    if (std::optional<Bits> src = evaluate(ext.getIn())) {
      result = *src;
      result->append(width - src->size(), BitValue::makeConstant(false));
    }
  } else if (auto trunc = dyn_cast<arith::TruncIOp>(def)) {
    if (std::optional<Bits> src = evaluate(trunc.getIn())) {
      result = Bits(src->begin(), src->begin() + width);
    }
  } else if (isa<arith::ShLIOp, arith::ShRUIOp>(def)) {
    std::optional<Bits> src = evaluate(def->getOperand(0));
    std::optional<Bits> amountBits = evaluate(def->getOperand(1));
    if (src && amountBits) {
      uint64_t amount = 0;
      bool amountConstant = true;
      for (unsigned j = 0; j < amountBits->size(); ++j) {
        BitValue bit = (*amountBits)[j];
        if (!bit.isConstant()) {
          amountConstant = false;
          break;
        }
        amount |= static_cast<uint64_t>(bit.flag) << j;
      }
      if (!amountConstant || amount > width) {
        return fail(def, "shift by non-constant amount");
      }
      Bits shifted(width, BitValue::makeConstant(false));
      for (unsigned j = 0; j + amount < width; ++j) {
        if (isa<arith::ShLIOp>(def)) {
          shifted[j + amount] = (*src)[j];
        } else {
          shifted[j] = (*src)[j + amount];
        }
      }
      result = shifted;
    }
  } else if (auto orOp = dyn_cast<arith::OrIOp>(def)) {
    std::optional<Bits> lhs = evaluate(orOp.getLhs());
    std::optional<Bits> rhs = evaluate(orOp.getRhs());
    if (lhs && rhs) {
      Bits bits;
      for (unsigned j = 0; j < width; ++j) {
        BitValue l = (*lhs)[j];
        BitValue r = (*rhs)[j];
        if (l.isConstant() && r.isConstant()) {
          bits.push_back(BitValue::makeConstant(l.flag || r.flag));
        } else if (l.isConstant()) {
          bits.push_back(l.flag ? BitValue::makeConstant(true) : r);
        } else if (r.isConstant()) {
          bits.push_back(r.flag ? BitValue::makeConstant(true) : l);
        } else {
          return fail(def, "'or' of overlapping input bits");
        }
      }
      result = bits;
    }
  } else if (auto xorOp = dyn_cast<arith::XOrIOp>(def)) {
    std::optional<Bits> lhs = evaluate(xorOp.getLhs());
    std::optional<Bits> rhs = evaluate(xorOp.getRhs());
    if (lhs && rhs) {
      Bits bits;
      for (unsigned j = 0; j < width; ++j) {
        BitValue l = (*lhs)[j];
        BitValue r = (*rhs)[j];
        if (l.isConstant() && r.isConstant()) {
          bits.push_back(BitValue::makeConstant(l.flag != r.flag));
        } else if (l.isConstant() || r.isConstant()) {
          BitValue inputBit = l.isConstant() ? r : l;
          bool toggle = l.isConstant() ? l.flag : r.flag;
          bits.push_back(BitValue::makeInput(inputBit.input, inputBit.flag != toggle));
        } else {
          return fail(def, "'xor' of two input bits");
        }
      }
      result = bits;
    }
  } else if (auto andOp = dyn_cast<arith::AndIOp>(def)) {
    std::optional<Bits> lhs = evaluate(andOp.getLhs());
    std::optional<Bits> rhs = evaluate(andOp.getRhs());
    if (lhs && rhs) {
      Bits bits;
      for (unsigned j = 0; j < width; ++j) {
        BitValue l = (*lhs)[j];
        BitValue r = (*rhs)[j];
        if (l.isConstant() && !l.flag) {
          bits.push_back(BitValue::makeConstant(false));
        } else if (r.isConstant() && !r.flag) {
          bits.push_back(BitValue::makeConstant(false));
        } else if (l.isConstant()) {
          bits.push_back(r);
        } else if (r.isConstant()) {
          bits.push_back(l);
        } else {
          return fail(def, "'and' of two input bits");
        }
      }
      result = bits;
    }
  } else if (isa<func::CallIndirectOp>(def)) {
    return fail(def, "indirect call inside prelimhlep.lin body; requires inlining a constant callee");
  } else if (isa<func::CallOp>(def)) {
    return fail(def, "call inside prelimhlep.lin body survived inlining");
  } else {
    return fail(def, "unrecognized op in prelimhlep.lin body");
  }

  if (result) {
    cache[value] = *result;
  }
  return result;
}
