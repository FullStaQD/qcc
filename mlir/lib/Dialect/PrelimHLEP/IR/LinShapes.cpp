// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/PrelimHLEP/IR/LinShapes.h"

#include <cmath>
#include <mlir/Dialect/Arith/IR/Arith.h>
#include <mlir/Dialect/Complex/IR/Complex.h>
#include <mlir/Dialect/Func/IR/FuncOps.h>
#include <mlir/Dialect/SCF/IR/SCF.h>
#include <mlir/IR/Matchers.h>

using namespace mlir;
using namespace qcc::prelimhlep;

//===----------------------------------------------------------------------===//
// LinBitEvaluator
//===----------------------------------------------------------------------===//

bool qcc::prelimhlep::isLinArithmeticOp(Operation* op) {
  return isa<arith::ConstantOp, arith::ExtUIOp, arith::TruncIOp, arith::ShLIOp, arith::ShRUIOp, arith::OrIOp,
             arith::XOrIOp, arith::AndIOp>(op);
}

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

  auto intType = dyn_cast<IntegerType>(value.getType());
  if (!intType || intType.getWidth() > 64) {
    return fail(op, "cannot interpret non-integer value");
  }
  unsigned width = intType.getWidth();

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
  if (auto ext = dyn_cast<arith::ExtUIOp>(def)) {
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

//===----------------------------------------------------------------------===//
// Shape verification
//===----------------------------------------------------------------------===//

namespace {

bool isLinOf(Type type, function_ref<bool(Type)> elementPredicate) {
  auto lin = dyn_cast<LinType>(type);
  return lin && elementPredicate(lin.getElementType());
}

bool isLinI1(Type type) {
  return isLinOf(type, [](Type element) { return element.isSignlessInteger(1); });
}

std::optional<int64_t> getLinIntWidth(Type type) {
  auto lin = dyn_cast<LinType>(type);
  if (!lin) {
    return std::nullopt;
  }
  auto intType = dyn_cast<IntegerType>(lin.getElementType());
  if (!intType) {
    return std::nullopt;
  }
  return intType.getWidth();
}

/// Verification context for one tagged op: bundles the op, the shape name
/// for diagnostics, and the body pieces every check needs.
struct ShapeCheck {
  LinOp op;
  StringRef name;
  Block& body;
  OutputOp output;

  ShapeCheck(LinOp op, StringRef name)
      : op(op), name(name), body(op.getBody().front()), output(cast<OutputOp>(body.getTerminator())) {}

  InFlightDiagnostic error(const Twine& message) { return op.emitOpError("tagged '") << name << "' but " << message; }

  LogicalResult checkOperandsAreQubits() {
    for (Value operand : op.getDelinearizedOperands()) {
      if (!isLinI1(operand.getType())) {
        return error("has a delinearized operand of type ") << operand.getType() << ", expected '!prelimhlep.lin<i1>'";
      }
    }
    return success();
  }

  LogicalResult checkNumOperands(unsigned expected) {
    if (op.getDelinearizedOperands().size() != expected) {
      return error("has ") << op.getDelinearizedOperands().size() << " delinearized operands, expected " << expected;
    }
    return success();
  }

  LogicalResult checkResultTypes(ArrayRef<Type> expected) {
    if (op.getResultTypes() != expected) {
      InFlightDiagnostic diag = error("has result types (");
      llvm::interleaveComma(op.getResultTypes(), diag);
      diag << "), expected (";
      llvm::interleaveComma(expected, diag);
      return diag << ")";
    }
    return success();
  }

  LogicalResult checkOutputCounts(unsigned delinearized, unsigned auxiliary) {
    if (output.getDelinearizedResults().size() != delinearized || output.getAuxiliaryResults().size() != auxiliary) {
      return error("outputs ") << output.getDelinearizedResults().size() << " delinearized and "
                               << output.getAuxiliaryResults().size() << " auxiliary results, expected " << delinearized
                               << " and " << auxiliary;
    }
    return success();
  }

  /// Every non-terminator body op must be one of the ops the bit evaluator
  /// understands.
  LogicalResult checkArithmeticBody() {
    for (Operation& nested : body.without_terminator()) {
      if (!isLinArithmeticOp(&nested)) {
        return nested.emitOpError("is not allowed in the body of a '") << name << "'-shaped 'prelimhlep.lin'";
      }
    }
    return success();
  }

  /// The body holds exactly one op, an `scf.if` on the given condition
  /// whose branches both hold `then`/`else` ops of the given counts.
  FailureOr<scf::IfOp> checkSingleIf(Value condition, unsigned numResults) {
    if (std::distance(body.begin(), body.end()) != 2) {
      return error("the body does not consist of a single 'scf.if'");
    }
    auto ifOp = dyn_cast<scf::IfOp>(body.front());
    if (!ifOp) {
      return error("the body does not consist of a single 'scf.if'");
    }
    if (ifOp.getCondition() != condition) {
      return error("the 'scf.if' does not branch on the expected bit");
    }
    if (ifOp.getNumResults() != numResults || !ifOp.elseBlock()) {
      return error("the 'scf.if' does not have ") << numResults << " results and an else-branch";
    }
    return ifOp;
  }

  /// Evaluates the delinearized outputs and compares them against the
  /// expected symbolic bits.
  LogicalResult checkOutputBits(ArrayRef<Bits> expected) {
    LinBitEvaluator evaluator(op);
    if (!evaluator.isValid()) {
      return error("has a non-integer delinearized value");
    }
    for (auto [index, pair] : llvm::enumerate(llvm::zip_equal(output.getDelinearizedResults(), expected))) {
      auto [value, bits] = pair;
      std::optional<Bits> actual = evaluator.evaluate(value);
      if (!actual) {
        return evaluator.getFailureOp()->emitOpError() << evaluator.getFailureMessage();
      }
      if (*actual != bits) {
        return error("delinearized output #") << index << " does not compute the expected bits";
      }
    }
    return success();
  }
};

LogicalResult verifyAlloc(ShapeCheck& check) {
  Type qubit = LinType::get(check.op.getContext(), IntegerType::get(check.op.getContext(), 1));
  if (failed(check.checkNumOperands(0)) || failed(check.checkResultTypes({qubit})) ||
      failed(check.checkOutputCounts(1, 0)) || failed(check.checkArithmeticBody())) {
    return failure();
  }
  return check.checkOutputBits({Bits{BitValue::makeConstant(false)}});
}

LogicalResult verifySplit(ShapeCheck& check) {
  if (failed(check.checkNumOperands(1))) {
    return failure();
  }
  std::optional<int64_t> width = getLinIntWidth(check.op.getDelinearizedOperands()[0].getType());
  if (!width) {
    return check.error("the operand is not a '!prelimhlep.lin<i<n>>'");
  }
  Type qubit = LinType::get(check.op.getContext(), IntegerType::get(check.op.getContext(), 1));
  SmallVector<Type> resultTypes(*width, qubit);
  if (failed(check.checkResultTypes(resultTypes)) || failed(check.checkOutputCounts(*width, 0)) ||
      failed(check.checkArithmeticBody())) {
    return failure();
  }
  SmallVector<Bits> expected;
  for (int64_t j = 0; j < *width; ++j) {
    expected.push_back({BitValue::makeInput(j, false)});
  }
  return check.checkOutputBits(expected);
}

LogicalResult verifyJoin(ShapeCheck& check) {
  unsigned width = check.op.getDelinearizedOperands().size();
  if (width == 0) {
    return check.error("has no delinearized operands");
  }
  if (failed(check.checkOperandsAreQubits())) {
    return failure();
  }
  Type result = LinType::get(check.op.getContext(), IntegerType::get(check.op.getContext(), width));
  if (failed(check.checkResultTypes({result})) || failed(check.checkOutputCounts(1, 0)) ||
      failed(check.checkArithmeticBody())) {
    return failure();
  }
  Bits expected;
  for (unsigned j = 0; j < width; ++j) {
    expected.push_back(BitValue::makeInput(j, false));
  }
  return check.checkOutputBits({expected});
}

LogicalResult verifyX(ShapeCheck& check) {
  Type qubit = LinType::get(check.op.getContext(), IntegerType::get(check.op.getContext(), 1));
  if (failed(check.checkNumOperands(1)) || failed(check.checkOperandsAreQubits()) ||
      failed(check.checkResultTypes({qubit})) || failed(check.checkOutputCounts(1, 0)) ||
      failed(check.checkArithmeticBody())) {
    return failure();
  }
  return check.checkOutputBits({Bits{BitValue::makeInput(0, true)}});
}

LogicalResult verifyMeasure(ShapeCheck& check, bool keep) {
  MLIRContext* ctx = check.op.getContext();
  Type bit = IntegerType::get(ctx, 1);
  Type qubit = LinType::get(ctx, bit);
  SmallVector<Type> resultTypes;
  if (keep) {
    resultTypes.push_back(qubit);
  }
  resultTypes.push_back(bit);
  if (failed(check.checkNumOperands(1)) || failed(check.checkOperandsAreQubits()) ||
      failed(check.checkResultTypes(resultTypes)) || failed(check.checkOutputCounts(keep ? 1 : 0, 1))) {
    return failure();
  }
  if (!check.body.without_terminator().empty()) {
    return check.error("the body is not empty");
  }
  Value arg = check.body.getArgument(0);
  if (check.output.getAuxiliaryResults()[0] != arg || (keep && check.output.getDelinearizedResults()[0] != arg)) {
    return check.error("the output does not pass the input bit through");
  }
  return success();
}

LogicalResult verifyHadamard(ShapeCheck& check) {
  if (failed(check.checkNumOperands(1)) || failed(check.checkOperandsAreQubits()) ||
      failed(check.checkOutputCounts(0, 1))) {
    return failure();
  }
  Type resultType = check.op.getResultTypes().size() == 1 ? check.op.getResultTypes()[0] : nullptr;
  bool isX = resultType && isLinOf(resultType, [](Type element) {
               auto x = dyn_cast<XType>(element);
               return x && x.getSize() == 1;
             });
  bool isY = resultType && isLinOf(resultType, [](Type element) {
               auto y = dyn_cast<YType>(element);
               return y && y.getSize() == 1;
             });
  if (!isX && !isY) {
    return check.error("the result is not a single-symbol X- or Y-basis 'lin' type");
  }
  FailureOr<scf::IfOp> ifOp = check.checkSingleIf(check.body.getArgument(0), 1);
  if (failed(ifOp)) {
    return failure();
  }
  if (check.output.getAuxiliaryResults()[0] != ifOp->getResult(0)) {
    return check.error("the output does not carry the 'scf.if' result");
  }
  auto checkBranch = [&](Block* block, StringRef symbol) -> LogicalResult {
    auto yield = cast<scf::YieldOp>(block->getTerminator());
    auto constant = yield.getOperand(0).getDefiningOp<ConstantOp>();
    if (!constant || constant->getBlock() != block || std::distance(block->begin(), block->end()) != 2) {
      return check.error("a branch does not consist of a single 'prelimhlep.constant'");
    }
    if (constant.getValue() != symbol) {
      return check.error("a branch yields the wrong basis symbol");
    }
    return success();
  };
  StringRef first = isY ? "->" : "+";
  StringRef second = isY ? "<-" : "-";
  return success(succeeded(checkBranch(ifOp->thenBlock(), second)) && succeeded(checkBranch(ifOp->elseBlock(), first)));
}

/// The `phase` gate body: `%r = scf.if %bit -> i1 { scale by a constant
/// unit-modulus factor } else { pass through }`.
FailureOr<scf::IfOp> checkPhaseIf(ShapeCheck& check, Block& body, Value bit) {
  FailureOr<scf::IfOp> ifOp = check.checkSingleIf(bit, 1);
  if (failed(ifOp)) {
    return failure();
  }
  if (!ifOp->getResult(0).getType().isSignlessInteger(1)) {
    return check.error("the 'scf.if' result is not an 'i1'");
  }
  Block* thenBlock = ifOp->thenBlock();
  auto thenYield = cast<scf::YieldOp>(thenBlock->getTerminator());
  auto elseYield = cast<scf::YieldOp>(ifOp->elseBlock()->getTerminator());
  auto scale = thenYield.getOperand(0).getDefiningOp<ScaleOp>();
  auto factor = scale ? scale.getFactor().getDefiningOp<complex::ConstantOp>() : nullptr;
  if (!scale || !factor || scale->getBlock() != thenBlock || factor->getBlock() != thenBlock ||
      scale.getInput() != bit || elseYield.getOperand(0) != bit ||
      std::distance(thenBlock->begin(), thenBlock->end()) != 3) {
    return check.error("the branches are not 'scale by a constant' and 'pass through'");
  }
  double re = cast<FloatAttr>(factor.getValue()[0]).getValueAsDouble();
  double im = cast<FloatAttr>(factor.getValue()[1]).getValueAsDouble();
  if (std::abs(std::hypot(re, im) - 1.0) > 1e-9) {
    return check.error("the scale factor does not have unit modulus");
  }
  (void)body;
  return ifOp;
}

LogicalResult verifyPhase(ShapeCheck& check) {
  Type qubit = LinType::get(check.op.getContext(), IntegerType::get(check.op.getContext(), 1));
  if (failed(check.checkNumOperands(1)) || failed(check.checkOperandsAreQubits()) ||
      failed(check.checkResultTypes({qubit})) || failed(check.checkOutputCounts(1, 0))) {
    return failure();
  }
  FailureOr<scf::IfOp> ifOp = checkPhaseIf(check, check.body, check.body.getArgument(0));
  if (failed(ifOp)) {
    return failure();
  }
  if (check.output.getDelinearizedResults()[0] != ifOp->getResult(0)) {
    return check.error("the output is not the 'scf.if' result");
  }
  return success();
}

/// Walks back the `arith.andi` chain `((a0 & a1) & a2) & ...` over the
/// block arguments; returns the number of chained ops or `nullopt`.
std::optional<unsigned> matchAndChain(Value cond, Block& body) {
  unsigned n = body.getNumArguments();
  unsigned ops = 0;
  for (unsigned i = n; i-- > 1;) {
    auto andOp = cond.getDefiningOp<arith::AndIOp>();
    if (!andOp || andOp->getBlock() != &body || andOp.getRhs() != body.getArgument(i)) {
      return std::nullopt;
    }
    cond = andOp.getLhs();
    ++ops;
  }
  if (cond != body.getArgument(0)) {
    return std::nullopt;
  }
  return ops;
}

LogicalResult verifyCtrl(ShapeCheck& check) {
  unsigned numControls = check.op.getDelinearizedOperands().size();
  if (numControls == 0) {
    return check.error("has no control operands");
  }
  Type qubit = LinType::get(check.op.getContext(), IntegerType::get(check.op.getContext(), 1));
  SmallVector<Type> resultTypes(numControls + 1, qubit);
  if (failed(check.checkOperandsAreQubits()) || failed(check.checkResultTypes(resultTypes)) ||
      failed(check.checkOutputCounts(numControls, 1))) {
    return failure();
  }
  for (auto [out, arg] : llvm::zip_equal(check.output.getDelinearizedResults(), check.body.getArguments())) {
    if (out != arg) {
      return check.error("the control bits are not passed through in order");
    }
  }

  // Body: the and-chain (numControls - 1 ops) followed by the scf.if.
  auto ifOp = dyn_cast<scf::IfOp>(check.body.getTerminator()->getPrevNode());
  if (!ifOp || std::distance(check.body.begin(), check.body.end()) != numControls + 1) {
    return check.error("the body does not consist of the control conjunction followed by a single 'scf.if'");
  }
  std::optional<unsigned> chain = matchAndChain(ifOp.getCondition(), check.body);
  if (!chain || *chain != numControls - 1) {
    return check.error("the 'scf.if' does not branch on the conjunction of all control bits");
  }
  if (ifOp.getNumResults() != 1 || !ifOp.elseBlock() || check.output.getAuxiliaryResults()[0] != ifOp.getResult(0)) {
    return check.error("the output does not carry the single 'scf.if' result");
  }

  Block* thenBlock = ifOp.thenBlock();
  auto thenYield = cast<scf::YieldOp>(thenBlock->getTerminator());
  auto elseYield = cast<scf::YieldOp>(ifOp.elseBlock()->getTerminator());
  auto gate = thenYield.getOperand(0).getDefiningOp<LinOp>();
  if (!gate || gate->getBlock() != thenBlock || std::distance(thenBlock->begin(), thenBlock->end()) != 2) {
    return check.error("the then-branch does not consist of a single tagged 'prelimhlep.lin'");
  }
  std::optional<LinShape> gateShape = gate.getShape();
  if (!gateShape || (*gateShape != LinShape::X && *gateShape != LinShape::Phase)) {
    return check.error("the controlled gate is not an 'x'- or 'phase'-shaped 'prelimhlep.lin'");
  }
  Value target = elseYield.getOperand(0);
  if (gate.getDelinearizedOperands().size() != 1 || gate.getDelinearizedOperands()[0] != target ||
      gate.getNumResults() != 1) {
    return check.error("the controlled gate is not applied to the value the else-branch passes through");
  }
  if (target.getParentRegion()->isProperAncestor(&check.op.getBody()) == false) {
    return check.error("the target is not captured from outside the op");
  }
  return success();
}

} // namespace

LogicalResult qcc::prelimhlep::verifyLinShape(LinOp op) {
  std::optional<LinShape> shape = op.getShape();
  if (!shape) {
    return success();
  }
  ShapeCheck check(op, stringifyLinShape(*shape));
  switch (*shape) {
  case LinShape::Alloc:
    return verifyAlloc(check);
  case LinShape::Split:
    return verifySplit(check);
  case LinShape::Join:
    return verifyJoin(check);
  case LinShape::X:
    return verifyX(check);
  case LinShape::Measure:
    return verifyMeasure(check, /*keep=*/true);
  case LinShape::MeasureDrop:
    return verifyMeasure(check, /*keep=*/false);
  case LinShape::Hadamard:
    return verifyHadamard(check);
  case LinShape::Phase:
    return verifyPhase(check);
  case LinShape::Ctrl:
    return verifyCtrl(check);
  }
  llvm_unreachable("unknown LinShape");
}

//===----------------------------------------------------------------------===//
// Accessors
//===----------------------------------------------------------------------===//

scf::IfOp qcc::prelimhlep::getShapeIf(LinOp op) {
  return cast<scf::IfOp>(op.getBody().front().getTerminator()->getPrevNode());
}

std::pair<double, double> qcc::prelimhlep::getPhaseShapeFactor(LinOp op) {
  auto yield = cast<scf::YieldOp>(getShapeIf(op).thenBlock()->getTerminator());
  auto scale = cast<ScaleOp>(yield.getOperand(0).getDefiningOp());
  auto factor = cast<complex::ConstantOp>(scale.getFactor().getDefiningOp());
  return {cast<FloatAttr>(factor.getValue()[0]).getValueAsDouble(),
          cast<FloatAttr>(factor.getValue()[1]).getValueAsDouble()};
}

LinOp qcc::prelimhlep::getCtrlShapeGate(LinOp op) {
  auto yield = cast<scf::YieldOp>(getShapeIf(op).thenBlock()->getTerminator());
  return cast<LinOp>(yield.getOperand(0).getDefiningOp());
}

Value qcc::prelimhlep::getCtrlShapeTarget(LinOp op) {
  return cast<scf::YieldOp>(getShapeIf(op).elseBlock()->getTerminator()).getOperand(0);
}
