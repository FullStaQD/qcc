// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// Lowers PrelimHLEP to the MQT-core QCO (value-semantics) dialect.
//
// The lowering is a manual per-function rewrite rather than a dialect
// conversion: `prelimhlep.lin` bodies capture linear values from the
// enclosing scope without listing them as operands, which the conversion
// framework cannot remap, while the halo invariants (single-block
// functions, every linear value used exactly once) make a single linear
// scan per function sufficient.
//
// Types are converted 1:N: `!prelimhlep.lin<i<n>>` (and the X-/Y-basis
// variants) become `n` individual `!qco.qubit` values, least-significant
// bit first. A `!qco.qubit` always holds the physical state; the X-/Y-basis
// element types are purely static tags, so `prelimhlep.base_change` lowers
// to nothing and basis rotations are only emitted where states are created.
//
// `prelimhlep.lin` bodies are recognized against a pattern library (see
// LinLowering below); unrecognized bodies are diagnosed, not synthesized.
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/PrelimHLEPToQCO/PrelimHLEPToQCO.h"

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Complex/IR/Complex.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/QCO/IR/QCODialect.h"
#include "mlir/Dialect/QCO/IR/QCOOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/APInt.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <cmath>
#include <cstdint>
#include <optional>
#include <utility>

namespace qcc {
using namespace mlir;
namespace hlep = qcc::prelimhlep;

#define GEN_PASS_DEF_PRELIMHLEPTOQCO
#include "qcc/Conversion/PrelimHLEPToQCO/PrelimHLEPToQCO.h.inc"

namespace {

constexpr llvm::StringLiteral kHaloAttrName = "prelimhlep.halo";

/// Number of qubits a PrelimHLEP `lin` type expands to, or `std::nullopt`
/// for non-lin types (including `!prelimhlep.unit`) and lin types over
/// unsupported element types.
std::optional<int64_t> getLinWidth(Type type) {
  auto linType = dyn_cast<hlep::LinType>(type);
  if (!linType) {
    return std::nullopt;
  }
  Type element = linType.getElementType();
  if (auto intType = dyn_cast<IntegerType>(element)) {
    return intType.getWidth();
  }
  if (auto xType = dyn_cast<hlep::XType>(element)) {
    return xType.getSize();
  }
  if (auto yType = dyn_cast<hlep::YType>(element)) {
    return yType.getSize();
  }
  return std::nullopt;
}

bool isPrelimHLEPType(Type type) { return isa_and_nonnull<hlep::PrelimHLEPDialect>(type.getDialect()); }

/// Appends the QCO expansion of `type` to `out`: lin types become qubits,
/// unit vanishes, everything else stays. Fails on unsupported lin element
/// types.
LogicalResult expandType(Type type, SmallVectorImpl<Type>& out) {
  if (isa<hlep::UnitType>(type)) {
    return success();
  }
  if (isa<hlep::LinType>(type)) {
    std::optional<int64_t> width = getLinWidth(type);
    if (!width) {
      return failure();
    }
    out.append(*width, qco::QubitType::get(type.getContext()));
    return success();
  }
  if (isPrelimHLEPType(type)) {
    return failure();
  }
  out.push_back(type);
  return success();
}

/// Symbolic value of a single classical bit inside a `lin` body: either a
/// known constant, or a (possibly negated) input bit of the enclosing
/// `prelimhlep.lin` (indexed into the flattened list of delinearized input
/// bits).
struct BitValue {
  enum class Kind { Constant, Input };
  Kind kind;
  /// For Constant: the bit. For Input: whether the bit is negated.
  bool flag;
  /// For Input: the flattened input bit index.
  unsigned input = 0;

  static BitValue makeConstant(bool value) { return {Kind::Constant, value, 0}; }
  static BitValue makeInput(unsigned index, bool negated) { return {Kind::Input, negated, index}; }

  bool isConstant() const { return kind == Kind::Constant; }
  bool isInput() const { return kind == Kind::Input; }

  bool operator==(const BitValue& other) const {
    return kind == other.kind && flag == other.flag && input == other.input;
  }
};

using Bits = SmallVector<BitValue>;

/// A conjunction of required input bit values, as (input bit, required
/// value) pairs sorted by input bit index.
using Predicate = SmallVector<std::pair<unsigned, bool>>;

/// Per-function lowering state: maps every not-yet-erased PrelimHLEP-typed
/// SSA value to the list of qubit values (LSB first) it lowers to.
using QubitMap = DenseMap<Value, SmallVector<Value>>;

//===----------------------------------------------------------------------===//
// LinLowering: the `prelimhlep.lin` body pattern library
//===----------------------------------------------------------------------===//

/// Recognizes and lowers a single `prelimhlep.lin` op. The body is
/// interpreted symbolically: every classical integer value is mapped to a
/// vector of `BitValue`s over the flattened delinearized input bits. On top
/// of that, at most one `scf.if` is handled structurally, covering the
/// conditional-phase, conditional-unitary, and basis-conditional-constant
/// shapes. Everything the interpretation cannot express is diagnosed.
class LinLowering {
public:
  LinLowering(hlep::LinOp op, OpBuilder& builder, QubitMap& qubitMap)
      : op(op), builder(builder), qubitMap(qubitMap), loc(op.getLoc()) {}

  LogicalResult run();

private:
  Type qubitType() { return qco::QubitType::get(op.getContext()); }

  std::optional<Bits> evalBits(Value value);
  std::optional<Predicate> evalPredicate(Value cond);

  LogicalResult classifyIf(scf::IfOp ifOp);
  LogicalResult lowerConditionalPhase(scf::IfOp ifOp, const Predicate& predicate);
  LogicalResult lowerConditionalConstant(scf::IfOp ifOp, const Predicate& predicate);
  LogicalResult lowerConditionalUnitary(scf::IfOp ifOp, const Predicate& predicate);

  LogicalResult emitMeasurements(ValueRange auxResults);
  FailureOr<SmallVector<Value>> emitDelinearizedResult(Value output);
  Value buildClassicalValue(const Bits& bits, Type type);

  Value emitX(Value qubit) { return qco::XOp::create(builder, loc, qubitType(), qubit); }

  /// Applies `qco.x` to every predicate qubit whose required value is 0 and
  /// returns the control qubits in predicate order (to be undone by
  /// `undoPolarityConjugation` on the ctrl outputs).
  SmallVector<Value> applyPolarityConjugation(const Predicate& predicate);
  void undoPolarityConjugation(const Predicate& predicate, ValueRange controlsOut);

  hlep::LinOp op;
  OpBuilder& builder;
  QubitMap& qubitMap;
  Location loc;

  /// Current qubit value per flattened input bit.
  SmallVector<Value> current;
  /// Input bits already consumed by an output (or a structural pattern).
  SmallVector<bool> used;
  /// Input bits that have been measured; `measuredBit[k]` is the i1 result.
  SmallVector<bool> measured;
  SmallVector<Value> measuredBit;

  /// Memoized symbolic evaluation of classical values in the body.
  DenseMap<Value, Bits> bitsCache;
  /// Qubit lists for linear-typed `scf.if` results handled structurally.
  DenseMap<Value, SmallVector<Value>> structuralResults;
};

std::optional<Bits> LinLowering::evalBits(Value value) {
  if (auto it = bitsCache.find(value); it != bitsCache.end()) {
    return it->second;
  }

  auto intType = dyn_cast<IntegerType>(value.getType());
  if (!intType || intType.getWidth() > 64) {
    op.emitError("unrecognized prelimhlep.lin body: cannot interpret non-integer value");
    return std::nullopt;
  }
  unsigned width = intType.getWidth();

  APInt constant;
  if (matchPattern(value, m_ConstantInt(&constant))) {
    Bits bits;
    for (unsigned j = 0; j < width; ++j) {
      bits.push_back(BitValue::makeConstant(constant[j]));
    }
    bitsCache[value] = bits;
    return bits;
  }

  Operation* def = value.getDefiningOp();
  if (!def) {
    op.emitError("unrecognized prelimhlep.lin body: value is not derived from the delinearized inputs");
    return std::nullopt;
  }

  std::optional<Bits> result;
  if (auto ext = dyn_cast<arith::ExtUIOp>(def)) {
    if (std::optional<Bits> src = evalBits(ext.getIn())) {
      result = *src;
      result->append(width - src->size(), BitValue::makeConstant(false));
    }
  } else if (auto trunc = dyn_cast<arith::TruncIOp>(def)) {
    if (std::optional<Bits> src = evalBits(trunc.getIn())) {
      result = Bits(src->begin(), src->begin() + width);
    }
  } else if (isa<arith::ShLIOp, arith::ShRUIOp>(def)) {
    std::optional<Bits> src = evalBits(def->getOperand(0));
    std::optional<Bits> amountBits = evalBits(def->getOperand(1));
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
        op.emitError("unrecognized prelimhlep.lin body: shift by non-constant amount");
        return std::nullopt;
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
    std::optional<Bits> lhs = evalBits(orOp.getLhs());
    std::optional<Bits> rhs = evalBits(orOp.getRhs());
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
          op.emitError("unrecognized prelimhlep.lin body: 'or' of overlapping input bits");
          return std::nullopt;
        }
      }
      result = bits;
    }
  } else if (auto xorOp = dyn_cast<arith::XOrIOp>(def)) {
    std::optional<Bits> lhs = evalBits(xorOp.getLhs());
    std::optional<Bits> rhs = evalBits(xorOp.getRhs());
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
          op.emitError("unrecognized prelimhlep.lin body: 'xor' of two input bits");
          return std::nullopt;
        }
      }
      result = bits;
    }
  } else if (auto andOp = dyn_cast<arith::AndIOp>(def)) {
    std::optional<Bits> lhs = evalBits(andOp.getLhs());
    std::optional<Bits> rhs = evalBits(andOp.getRhs());
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
          op.emitError("unrecognized prelimhlep.lin body: 'and' of two input bits");
          return std::nullopt;
        }
      }
      result = bits;
    }
  } else if (isa<func::CallIndirectOp>(def)) {
    def->emitError("indirect call inside prelimhlep.lin body; requires inlining a constant callee");
    return std::nullopt;
  } else if (isa<func::CallOp>(def)) {
    def->emitError("call inside prelimhlep.lin body survived inlining");
    return std::nullopt;
  } else {
    def->emitError("unrecognized op in prelimhlep.lin body");
    return std::nullopt;
  }

  if (result) {
    bitsCache[value] = *result;
  }
  return result;
}

std::optional<Predicate> LinLowering::evalPredicate(Value cond) {
  DenseMap<unsigned, bool> required;

  auto addRequirement = [&](unsigned input, bool value) -> bool {
    auto [it, inserted] = required.try_emplace(input, value);
    if (!inserted && it->second != value) {
      op.emitError("unrecognized prelimhlep.lin body: contradictory condition on an input bit");
      return false;
    }
    return true;
  };

  auto cmp = cond.getDefiningOp<arith::CmpIOp>();
  if (cmp && (cmp.getPredicate() == arith::CmpIPredicate::eq || cmp.getPredicate() == arith::CmpIPredicate::ne)) {
    std::optional<Bits> lhs = evalBits(cmp.getLhs());
    std::optional<Bits> rhs = evalBits(cmp.getRhs());
    if (!lhs || !rhs) {
      return std::nullopt;
    }
    auto allConstant = [](const Bits& bits) {
      return llvm::all_of(bits, [](BitValue bit) { return bit.isConstant(); });
    };
    Bits constantSide;
    Bits inputSide;
    if (allConstant(*rhs)) {
      constantSide = *rhs;
      inputSide = *lhs;
    } else if (allConstant(*lhs)) {
      constantSide = *lhs;
      inputSide = *rhs;
    } else {
      op.emitError("unrecognized prelimhlep.lin body: comparison of two non-constant values");
      return std::nullopt;
    }
    bool negate = cmp.getPredicate() == arith::CmpIPredicate::ne;
    if (negate && inputSide.size() != 1) {
      op.emitError("unrecognized prelimhlep.lin body: multi-bit 'ne' comparison");
      return std::nullopt;
    }
    for (unsigned j = 0; j < inputSide.size(); ++j) {
      bool requiredValue = constantSide[j].flag != negate;
      BitValue bit = inputSide[j];
      if (bit.isConstant()) {
        if (bit.flag != requiredValue) {
          op.emitError("unrecognized prelimhlep.lin body: condition is constant");
          return std::nullopt;
        }
        continue;
      }
      if (!addRequirement(bit.input, requiredValue != bit.flag)) {
        return std::nullopt;
      }
    }
  } else {
    std::optional<Bits> bits = evalBits(cond);
    if (!bits) {
      return std::nullopt;
    }
    BitValue bit = (*bits)[0];
    if (bit.isConstant()) {
      op.emitError("unrecognized prelimhlep.lin body: condition is constant");
      return std::nullopt;
    }
    if (!addRequirement(bit.input, !bit.flag)) {
      return std::nullopt;
    }
  }

  if (required.empty()) {
    op.emitError("unrecognized prelimhlep.lin body: condition does not constrain any input bit");
    return std::nullopt;
  }
  Predicate predicate(required.begin(), required.end());
  llvm::sort(predicate, [](const auto& a, const auto& b) { return a.first < b.first; });
  return predicate;
}

SmallVector<Value> LinLowering::applyPolarityConjugation(const Predicate& predicate) {
  SmallVector<Value> controls;
  for (auto [input, value] : predicate) {
    if (!value) {
      current[input] = emitX(current[input]);
    }
    controls.push_back(current[input]);
  }
  return controls;
}

void LinLowering::undoPolarityConjugation(const Predicate& predicate, ValueRange controlsOut) {
  for (auto [pair, control] : llvm::zip_equal(predicate, controlsOut)) {
    auto [input, value] = pair;
    current[input] = value ? control : emitX(control);
  }
}

/// Conditional phase: `scf.if %pred { scale by constant c } else
/// { passthrough }` over classical bits. Lowered to a (multi-)controlled
/// `qco.z` / `qco.p`, with X-conjugation on negative-polarity controls.
LogicalResult LinLowering::lowerConditionalPhase(scf::IfOp ifOp, const Predicate& predicate) {
  if (ifOp.getNumResults() != 1) {
    return op.emitError("unrecognized prelimhlep.lin body: conditional phase with multiple results");
  }
  auto thenYield = cast<scf::YieldOp>(ifOp.thenBlock()->getTerminator());
  auto elseYield = cast<scf::YieldOp>(ifOp.elseBlock()->getTerminator());

  auto scale = thenYield.getOperand(0).getDefiningOp<hlep::ScaleOp>();
  if (!scale) {
    return op.emitError("unrecognized prelimhlep.lin body: expected a scale in the conditional branch");
  }
  auto factorOp = scale.getFactor().getDefiningOp<complex::ConstantOp>();
  if (!factorOp) {
    return scale.emitError("non-constant scale factor inside prelimhlep.lin body");
  }
  double re = cast<FloatAttr>(factorOp.getValue()[0]).getValueAsDouble();
  double im = cast<FloatAttr>(factorOp.getValue()[1]).getValueAsDouble();
  if (std::abs(std::hypot(re, im) - 1.0) > 1e-9) {
    return scale.emitError("non-unit-modulus scale factor cannot be lowered to QCO");
  }
  double angle = std::atan2(im, re);

  std::optional<Bits> scaledBits = evalBits(scale.getInput());
  std::optional<Bits> elseBits = evalBits(elseYield.getOperand(0));
  if (!scaledBits || !elseBits) {
    return failure();
  }
  if (*scaledBits != *elseBits) {
    return op.emitError("unrecognized prelimhlep.lin body: conditional branches disagree on the passed-through bits");
  }

  SmallVector<Value> controls = applyPolarityConjugation(predicate);
  Value target = controls.pop_back_val();
  SmallVector<Value> controlsOut;
  Value targetOut;
  bool isMinusOne = std::abs(angle - M_PI) < 1e-9 || std::abs(angle + M_PI) < 1e-9;
  if (controls.empty()) {
    targetOut = isMinusOne ? qco::ZOp::create(builder, loc, qubitType(), target).getResult()
                           : qco::POp::create(builder, loc, target, angle).getResult();
  } else {
    auto ctrl =
        qco::CtrlOp::create(builder, loc, controls, ValueRange{target}, [&](ValueRange targets) -> SmallVector<Value> {
          Value result = isMinusOne ? qco::ZOp::create(builder, loc, qubitType(), targets[0]).getResult()
                                    : qco::POp::create(builder, loc, targets[0], angle).getResult();
          return {result};
        });
    controlsOut.append(ctrl.getControlsOut().begin(), ctrl.getControlsOut().end());
    targetOut = ctrl.getTargetsOut()[0];
  }
  controlsOut.push_back(targetOut);
  undoPolarityConjugation(predicate, controlsOut);

  bitsCache[ifOp.getResult(0)] = *elseBits;
  return success();
}

/// Basis-conditional constant (Hadamard family): `scf.if %bit` yielding a
/// one-symbol X- or Y-basis `prelimhlep.constant` in both branches. The
/// input qubit is transformed in place by `h` (optionally preceded by `x`,
/// optionally followed by `s` for the Y basis).
LogicalResult LinLowering::lowerConditionalConstant(scf::IfOp ifOp, const Predicate& predicate) {
  auto thenYield = cast<scf::YieldOp>(ifOp.thenBlock()->getTerminator());
  auto elseYield = cast<scf::YieldOp>(ifOp.elseBlock()->getTerminator());
  auto thenConstant = thenYield.getOperand(0).getDefiningOp<hlep::ConstantOp>();
  auto elseConstant = elseYield.getOperand(0).getDefiningOp<hlep::ConstantOp>();
  if (!thenConstant || !elseConstant || ifOp.getNumResults() != 1) {
    return op.emitError("unrecognized prelimhlep.lin body: conditional over linear values that is neither a "
                        "controlled unitary nor a basis-conditional constant");
  }
  if (predicate.size() != 1) {
    return op.emitError("unrecognized prelimhlep.lin body: basis-conditional constant with a multi-bit condition");
  }

  auto linType = cast<hlep::LinType>(ifOp.getResult(0).getType());
  bool isY = isa<hlep::YType>(linType.getElementType());
  // The second basis symbol is `-` for X and `<-` for Y.
  auto isSecondSymbol = [&](hlep::ConstantOp constant) { return constant.getValue().front() == '-' == !isY; };
  bool thenSecond = isSecondSymbol(thenConstant);
  bool elseSecond = isSecondSymbol(elseConstant);
  if (thenSecond == elseSecond) {
    return op.emitError("unrecognized prelimhlep.lin body: conditional constant does not depend on the condition");
  }

  auto [input, polarity] = predicate.front();
  // Symbol produced for input bit 0. `{0 -> first, 1 -> second}` is a plain
  // Hadamard; the swapped mapping is X followed by Hadamard.
  bool zeroSecond = polarity ? elseSecond : thenSecond;
  Value qubit = current[input];
  if (zeroSecond) {
    qubit = emitX(qubit);
  }
  qubit = qco::HOp::create(builder, loc, qubitType(), qubit);
  if (isY) {
    qubit = qco::SOp::create(builder, loc, qubitType(), qubit);
  }
  current[input] = qubit;
  used[input] = true;
  structuralResults[ifOp.getResult(0)] = {qubit};
  return success();
}

/// Conditional unitary: `scf.if %pred` applying a nested `prelimhlep.lin`
/// to captured linear values in the then-branch and passing them through in
/// the else-branch. The nested body must be a bit-permutation-free
/// negation of exactly one bit, so the `qco.ctrl` body holds a single
/// `qco.x` (the ctrl verifier admits exactly one unitary op).
LogicalResult LinLowering::lowerConditionalUnitary(scf::IfOp ifOp, const Predicate& predicate) {
  auto thenYield = cast<scf::YieldOp>(ifOp.thenBlock()->getTerminator());
  auto elseYield = cast<scf::YieldOp>(ifOp.elseBlock()->getTerminator());

  hlep::LinOp inner;
  for (Operation& nested : ifOp.thenBlock()->without_terminator()) {
    auto nestedLin = dyn_cast<hlep::LinOp>(nested);
    if (!nestedLin || inner) {
      return op.emitError("unrecognized prelimhlep.lin body: conditional branch is not a single nested linearization");
    }
    inner = nestedLin;
  }
  if (!inner || thenYield.getOperands() != inner.getResults() ||
      elseYield.getOperands() != inner.getDelinearizedOperands()) {
    return op.emitError("unrecognized prelimhlep.lin body: conditional branches do not apply and pass through the "
                        "same linear values");
  }

  // Interpret the nested body over its own delinearized inputs.
  LinLowering innerEval(inner, builder, qubitMap);
  Block& innerBody = inner.getBody().front();
  unsigned innerBits = 0;
  for (BlockArgument arg : innerBody.getArguments()) {
    auto intType = dyn_cast<IntegerType>(arg.getType());
    if (!intType) {
      return inner.emitError("unrecognized prelimhlep.lin body: non-integer delinearized value");
    }
    Bits bits;
    for (unsigned j = 0; j < intType.getWidth(); ++j) {
      bits.push_back(BitValue::makeInput(innerBits + j, false));
    }
    innerEval.bitsCache[arg] = bits;
    innerBits += intType.getWidth();
  }
  auto innerOutput = cast<hlep::OutputOp>(innerBody.getTerminator());
  if (!innerOutput.getAuxiliaryResults().empty()) {
    return inner.emitError("unrecognized prelimhlep.lin body: auxiliary results under a condition");
  }
  Bits innerResultBits;
  for (Value output : innerOutput.getDelinearizedResults()) {
    std::optional<Bits> bits = innerEval.evalBits(output);
    if (!bits) {
      return failure();
    }
    innerResultBits.append(*bits);
  }
  std::optional<unsigned> negatedBit;
  if (innerResultBits.size() != innerBits) {
    return inner.emitError("unrecognized prelimhlep.lin body: conditional unitary changes the number of qubits");
  }
  for (unsigned j = 0; j < innerResultBits.size(); ++j) {
    BitValue bit = innerResultBits[j];
    if (!bit.isInput() || bit.input != j) {
      return inner.emitError("unrecognized prelimhlep.lin body: conditional unitary permutes or allocates qubits");
    }
    if (bit.flag) {
      if (negatedBit) {
        return inner.emitError("unrecognized prelimhlep.lin body: conditional unitary needs more than one gate");
      }
      negatedBit = j;
    }
  }

  // Gather the captured target qubits, in nested-operand order.
  SmallVector<Value> targets;
  for (Value captured : inner.getDelinearizedOperands()) {
    auto it = qubitMap.find(captured);
    if (it == qubitMap.end()) {
      return op.emitError("unrecognized prelimhlep.lin body: conditional unitary target is not a captured linear "
                          "value");
    }
    targets.append(it->second.begin(), it->second.end());
  }

  SmallVector<Value> targetsOut;
  if (!negatedBit) {
    // Identity under a condition: nothing to emit.
    targetsOut = targets;
  } else {
    SmallVector<Value> controls = applyPolarityConjugation(predicate);
    auto ctrl =
        qco::CtrlOp::create(builder, loc, controls, targets, [&](ValueRange blockTargets) -> SmallVector<Value> {
          SmallVector<Value> yielded(blockTargets.begin(), blockTargets.end());
          yielded[*negatedBit] = emitX(yielded[*negatedBit]);
          return yielded;
        });
    undoPolarityConjugation(predicate, ctrl.getControlsOut());
    targetsOut.append(ctrl.getTargetsOut().begin(), ctrl.getTargetsOut().end());
  }

  // Slice the outputs back per if-result, following the else-branch
  // (pass-through) operand widths.
  unsigned offset = 0;
  for (auto [result, passthrough] : llvm::zip_equal(ifOp.getResults(), elseYield.getOperands())) {
    int64_t width = *getLinWidth(passthrough.getType());
    structuralResults[result] = SmallVector<Value>(targetsOut.begin() + offset, targetsOut.begin() + offset + width);
    offset += width;
  }
  return success();
}

LogicalResult LinLowering::classifyIf(scf::IfOp ifOp) {
  std::optional<Predicate> predicate = evalPredicate(ifOp.getCondition());
  if (!predicate) {
    return failure();
  }
  bool linearResults = llvm::any_of(ifOp.getResultTypes(), isPrelimHLEPType);
  if (!linearResults) {
    return lowerConditionalPhase(ifOp, *predicate);
  }
  auto thenYield = cast<scf::YieldOp>(ifOp.thenBlock()->getTerminator());
  if (thenYield.getNumOperands() == 1 && thenYield.getOperand(0).getDefiningOp<hlep::ConstantOp>()) {
    return lowerConditionalConstant(ifOp, *predicate);
  }
  return lowerConditionalUnitary(ifOp, *predicate);
}

LogicalResult LinLowering::emitMeasurements(ValueRange auxResults) {
  for (Value aux : auxResults) {
    if (isPrelimHLEPType(aux.getType())) {
      continue;
    }
    std::optional<Bits> bits = evalBits(aux);
    if (!bits) {
      return failure();
    }
    for (BitValue bit : *bits) {
      if (bit.isConstant() || measured[bit.input]) {
        continue;
      }
      auto measure = qco::MeasureOp::create(builder, loc, current[bit.input]);
      current[bit.input] = measure.getQubitOut();
      measured[bit.input] = true;
      measuredBit[bit.input] = measure.getResult();
    }
  }
  return success();
}

/// Materializes the qubit list for one delinearized output value: constant
/// bits become fresh allocations, input bits are (possibly negated and)
/// rewired.
FailureOr<SmallVector<Value>> LinLowering::emitDelinearizedResult(Value output) {
  std::optional<Bits> bits = evalBits(output);
  if (!bits) {
    return failure();
  }
  SmallVector<Value> qubits;
  for (BitValue bit : *bits) {
    if (bit.isConstant()) {
      Value qubit = qco::AllocOp::create(builder, loc);
      if (bit.flag) {
        qubit = emitX(qubit);
      }
      qubits.push_back(qubit);
      continue;
    }
    if (used[bit.input]) {
      return op.emitError("unrecognized prelimhlep.lin body: input bit used in more than one output");
    }
    used[bit.input] = true;
    Value qubit = current[bit.input];
    if (bit.flag) {
      qubit = emitX(qubit);
    }
    qubits.push_back(qubit);
  }
  return qubits;
}

/// Rebuilds a classical integer value from measured/constant bits.
Value LinLowering::buildClassicalValue(const Bits& bits, Type type) {
  unsigned width = cast<IntegerType>(type).getWidth();
  auto bitValue = [&](BitValue bit) -> Value {
    Value value = measuredBit[bit.input];
    if (bit.flag) {
      Value one = arith::ConstantOp::create(builder, loc, builder.getBoolAttr(true));
      value = arith::XOrIOp::create(builder, loc, value, one);
    }
    return value;
  };
  if (width == 1) {
    BitValue bit = bits.front();
    if (bit.isConstant()) {
      return arith::ConstantOp::create(builder, loc, builder.getBoolAttr(bit.flag));
    }
    return bitValue(bit);
  }

  uint64_t constantPart = 0;
  for (unsigned j = 0; j < width; ++j) {
    if (bits[j].isConstant() && bits[j].flag) {
      constantPart |= uint64_t(1) << j;
    }
  }
  Value accumulated = arith::ConstantOp::create(builder, loc, builder.getIntegerAttr(type, constantPart));
  for (unsigned j = 0; j < width; ++j) {
    BitValue bit = bits[j];
    if (bit.isConstant()) {
      continue;
    }
    Value extended = arith::ExtUIOp::create(builder, loc, type, bitValue(bit));
    if (j > 0) {
      Value amount = arith::ConstantOp::create(builder, loc, builder.getIntegerAttr(type, j));
      extended = arith::ShLIOp::create(builder, loc, extended, amount);
    }
    accumulated = arith::OrIOp::create(builder, loc, accumulated, extended);
  }
  return accumulated;
}

LogicalResult LinLowering::run() {
  Block& body = op.getBody().front();

  // Seed the flattened input bits from the delinearized operands.
  unsigned numBits = 0;
  for (auto [arg, operand] : llvm::zip_equal(body.getArguments(), op.getDelinearizedOperands())) {
    auto it = qubitMap.find(operand);
    if (it == qubitMap.end()) {
      return op.emitError("delinearized operand has no lowered qubits");
    }
    if (auto intType = dyn_cast<IntegerType>(arg.getType())) {
      Bits bits;
      for (unsigned j = 0; j < intType.getWidth(); ++j) {
        bits.push_back(BitValue::makeInput(numBits + j, false));
      }
      bitsCache[arg] = bits;
    } else {
      return op.emitError("unrecognized prelimhlep.lin body: non-integer delinearized value");
    }
    current.append(it->second.begin(), it->second.end());
    numBits += it->second.size();
  }
  used.assign(numBits, false);
  measured.assign(numBits, false);
  measuredBit.assign(numBits, Value());

  // Handle at most one structural scf.if.
  scf::IfOp structuralIf;
  for (Operation& nested : body.without_terminator()) {
    if (auto ifOp = dyn_cast<scf::IfOp>(nested)) {
      if (structuralIf) {
        return op.emitError("unrecognized prelimhlep.lin body: more than one conditional");
      }
      structuralIf = ifOp;
    }
  }
  if (structuralIf && failed(classifyIf(structuralIf))) {
    return failure();
  }

  auto output = cast<hlep::OutputOp>(body.getTerminator());

  if (failed(emitMeasurements(output.getAuxiliaryResults()))) {
    return failure();
  }

  // Delinearized (re-linearized) results.
  SmallVector<SmallVector<Value>> resultQubits;
  for (Value delinearized : output.getDelinearizedResults()) {
    FailureOr<SmallVector<Value>> qubits = emitDelinearizedResult(delinearized);
    if (failed(qubits)) {
      return failure();
    }
    resultQubits.push_back(std::move(*qubits));
  }

  // Auxiliary results: carried linear values pass through; classical values
  // are rebuilt from their measurement outcomes.
  SmallVector<std::optional<SmallVector<Value>>> auxQubits;
  SmallVector<Value> auxClassical;
  for (Value aux : output.getAuxiliaryResults()) {
    if (isPrelimHLEPType(aux.getType())) {
      auxClassical.push_back(Value());
      if (auto it = structuralResults.find(aux); it != structuralResults.end()) {
        auxQubits.push_back(it->second);
      } else if (auto it = qubitMap.find(aux); it != qubitMap.end()) {
        auxQubits.push_back(it->second);
      } else {
        return op.emitError("unrecognized prelimhlep.lin body: carried linear value is neither captured nor produced "
                            "by a recognized conditional");
      }
      continue;
    }
    std::optional<Bits> bits = evalBits(aux);
    if (!bits) {
      return failure();
    }
    auxQubits.push_back(std::nullopt);
    auxClassical.push_back(buildClassicalValue(*bits, aux.getType()));
  }

  // Sink measured-and-dropped qubits; diagnose silently discarded ones.
  for (unsigned k = 0; k < numBits; ++k) {
    if (used[k]) {
      continue;
    }
    if (measured[k]) {
      qco::SinkOp::create(builder, loc, current[k]);
    } else {
      return op.emitError("unrecognized prelimhlep.lin body: input bit is discarded without measurement");
    }
  }

  // Wire up the op's results: first the re-linearized delinearized results,
  // then the auxiliary results.
  unsigned resultIndex = 0;
  for (SmallVector<Value>& qubits : resultQubits) {
    qubitMap[op.getResult(resultIndex++)] = std::move(qubits);
  }
  for (auto [index, aux] : llvm::enumerate(output.getAuxiliaryResults())) {
    Value result = op.getResult(resultIndex++);
    if (auxQubits[index]) {
      qubitMap[result] = std::move(*auxQubits[index]);
    } else {
      result.replaceAllUsesWith(auxClassical[index]);
    }
  }
  return success();
}

//===----------------------------------------------------------------------===//
// Per-function lowering
//===----------------------------------------------------------------------===//

class FunctionLowering {
public:
  FunctionLowering(func::FuncOp fn, const DenseMap<Operation*, FunctionType>& newSignatures)
      : fn(fn), newSignatures(newSignatures), builder(fn.getContext()) {}

  LogicalResult run();

private:
  LogicalResult lowerOp(Operation* operation);
  LogicalResult lowerConstant(hlep::ConstantOp constant);
  LogicalResult lowerExp(hlep::ExpOp exp);
  LogicalResult lowerCall(func::CallOp call);
  LogicalResult lowerReturn(func::ReturnOp ret);

  /// Looks up the qubit expansion of `value`; classical values expand to
  /// themselves.
  LogicalResult expandValue(Value value, SmallVectorImpl<Value>& out);

  Type qubitType() { return qco::QubitType::get(fn.getContext()); }

  func::FuncOp fn;
  const DenseMap<Operation*, FunctionType>& newSignatures;
  OpBuilder builder;
  QubitMap qubitMap;
  SmallVector<Operation*> opsToErase;
};

LogicalResult FunctionLowering::expandValue(Value value, SmallVectorImpl<Value>& out) {
  if (!isPrelimHLEPType(value.getType())) {
    out.push_back(value);
    return success();
  }
  auto it = qubitMap.find(value);
  if (it == qubitMap.end()) {
    return failure();
  }
  out.append(it->second.begin(), it->second.end());
  return success();
}

LogicalResult FunctionLowering::lowerConstant(hlep::ConstantOp constant) {
  Location loc = constant.getLoc();
  auto linType = cast<hlep::LinType>(constant.getType());
  bool isY = isa<hlep::YType>(linType.getElementType());

  // Parse the symbol string into per-qubit "second symbol" flags
  // (`-` for X, `<-` for Y; the first symbols are `+` and `->`).
  SmallVector<bool> secondSymbol;
  StringRef symbols = constant.getValue();
  while (!symbols.empty()) {
    if (isY) {
      secondSymbol.push_back(symbols.starts_with("<-"));
      symbols = symbols.drop_front(2);
    } else {
      secondSymbol.push_back(symbols.front() == '-');
      symbols = symbols.drop_front(1);
    }
  }

  SmallVector<Value> qubits;
  for (bool second : secondSymbol) {
    Value qubit = qco::AllocOp::create(builder, loc);
    if (second) {
      qubit = qco::XOp::create(builder, loc, qubitType(), qubit);
    }
    qubit = qco::HOp::create(builder, loc, qubitType(), qubit);
    if (isY) {
      qubit = qco::SOp::create(builder, loc, qubitType(), qubit);
    }
    qubits.push_back(qubit);
  }
  qubitMap[constant.getResult()] = std::move(qubits);
  opsToErase.push_back(constant);
  return success();
}

LogicalResult FunctionLowering::lowerExp(hlep::ExpOp exp) {
  Location loc = exp.getLoc();
  SmallVector<hlep::HamiltonianAttr::Term> terms = exp.getHamiltonian().getTerms();
  if (terms.size() != 1) {
    return exp.emitError("multi-term hamiltonians are not supported by the QCO lowering");
  }
  const hlep::HamiltonianAttr::Term& term = terms.front();

  auto it = qubitMap.find(exp.getInput());
  if (it == qubitMap.end()) {
    return exp.emitError("input has no lowered qubits");
  }
  SmallVector<Value> qubits = it->second;

  // exp(-i * angle * c * P) == r_P(2 * c * angle) for a Pauli product P,
  // and a global phase of -c * angle for the identity.
  auto scaledAngle = [&](double factor) -> Value {
    Value constant = arith::ConstantOp::create(builder, loc, builder.getF64FloatAttr(factor * term.coefficient));
    return arith::MulFOp::create(builder, loc, exp.getAngle(), constant);
  };

  if (term.factors.empty()) {
    qco::GPhaseOp::create(builder, loc, scaledAngle(-1.0));
  } else if (term.factors.size() == 1) {
    hlep::PauliFactor factor = term.factors.front();
    Value qubit = qubits[factor.qubit];
    Value angle = scaledAngle(2.0);
    Value rotated;
    switch (factor.kind) {
    case hlep::PauliKind::X:
      rotated = qco::RXOp::create(builder, loc, qubit, angle).getResult();
      break;
    case hlep::PauliKind::Y:
      rotated = qco::RYOp::create(builder, loc, qubit, angle).getResult();
      break;
    case hlep::PauliKind::Z:
      rotated = qco::RZOp::create(builder, loc, qubit, angle).getResult();
      break;
    }
    qubits[factor.qubit] = rotated;
  } else if (term.factors.size() == 2 && term.factors[0].kind == term.factors[1].kind) {
    hlep::PauliFactor first = term.factors[0];
    hlep::PauliFactor second = term.factors[1];
    Value angle = scaledAngle(2.0);
    Operation* rotation;
    switch (first.kind) {
    case hlep::PauliKind::X:
      rotation = qco::RXXOp::create(builder, loc, qubits[first.qubit], qubits[second.qubit], angle);
      break;
    case hlep::PauliKind::Y:
      rotation = qco::RYYOp::create(builder, loc, qubits[first.qubit], qubits[second.qubit], angle);
      break;
    case hlep::PauliKind::Z:
      rotation = qco::RZZOp::create(builder, loc, qubits[first.qubit], qubits[second.qubit], angle);
      break;
    }
    qubits[first.qubit] = rotation->getResult(0);
    qubits[second.qubit] = rotation->getResult(1);
  } else {
    return exp.emitError("only single-Pauli and equal-Pauli-pair hamiltonian terms are supported by the QCO "
                         "lowering");
  }

  qubitMap[exp.getResult()] = std::move(qubits);
  opsToErase.push_back(exp);
  return success();
}

LogicalResult FunctionLowering::lowerCall(func::CallOp call) {
  bool involvesPrelimHLEP =
      llvm::any_of(call.getOperandTypes(), isPrelimHLEPType) || llvm::any_of(call.getResultTypes(), isPrelimHLEPType);
  if (!involvesPrelimHLEP) {
    return success();
  }

  SmallVector<Value> newOperands;
  for (Value operand : call.getOperands()) {
    if (failed(expandValue(operand, newOperands))) {
      return call.emitError("operand has no lowered qubits");
    }
  }
  SmallVector<Type> newResultTypes;
  for (Type type : call.getResultTypes()) {
    if (failed(expandType(type, newResultTypes))) {
      return call.emitError("result type cannot be lowered to QCO");
    }
  }

  auto newCall = func::CallOp::create(builder, call.getLoc(), call.getCalleeAttr(), newResultTypes, newOperands);

  unsigned newIndex = 0;
  for (Value result : call.getResults()) {
    if (auto width = getLinWidth(result.getType())) {
      qubitMap[result] =
          SmallVector<Value>(newCall.getResults().begin() + newIndex, newCall.getResults().begin() + newIndex + *width);
      newIndex += *width;
    } else if (isa<hlep::UnitType>(result.getType())) {
      qubitMap[result] = {};
    } else {
      result.replaceAllUsesWith(newCall.getResult(newIndex++));
    }
  }
  opsToErase.push_back(call);
  return success();
}

LogicalResult FunctionLowering::lowerReturn(func::ReturnOp ret) {
  if (llvm::none_of(ret.getOperandTypes(), isPrelimHLEPType)) {
    return success();
  }
  SmallVector<Value> newOperands;
  for (Value operand : ret.getOperands()) {
    if (failed(expandValue(operand, newOperands))) {
      return ret.emitError("operand has no lowered qubits");
    }
  }
  func::ReturnOp::create(builder, ret.getLoc(), newOperands);
  opsToErase.push_back(ret);
  return success();
}

LogicalResult FunctionLowering::lowerOp(Operation* operation) {
  builder.setInsertionPoint(operation);
  Location loc = operation->getLoc();

  if (auto unit = dyn_cast<hlep::UnitValueOp>(operation)) {
    qubitMap[unit.getResult()] = {};
    opsToErase.push_back(unit);
    return success();
  }
  if (auto baseChange = dyn_cast<hlep::BaseChangeOp>(operation)) {
    // A qubit always holds the physical state; the basis is a static tag.
    auto it = qubitMap.find(baseChange.getInput());
    if (it == qubitMap.end()) {
      return baseChange.emitError("input has no lowered qubits");
    }
    SmallVector<Value> qubits = it->second;
    qubitMap[baseChange.getResult()] = std::move(qubits);
    opsToErase.push_back(baseChange);
    return success();
  }
  if (auto constant = dyn_cast<hlep::ConstantOp>(operation)) {
    return lowerConstant(constant);
  }
  if (auto addPhase = dyn_cast<hlep::AddPhaseOp>(operation)) {
    qco::GPhaseOp::create(builder, loc, addPhase.getAlpha());
    auto it = qubitMap.find(addPhase.getInput());
    if (it == qubitMap.end()) {
      return addPhase.emitError("input has no lowered qubits");
    }
    SmallVector<Value> qubits = it->second;
    qubitMap[addPhase.getResult()] = std::move(qubits);
    opsToErase.push_back(addPhase);
    return success();
  }
  if (auto scale = dyn_cast<hlep::ScaleOp>(operation)) {
    auto factorOp = scale.getFactor().getDefiningOp<complex::ConstantOp>();
    if (!factorOp) {
      return scale.emitError("non-constant scale factor cannot be lowered to QCO");
    }
    double re = cast<FloatAttr>(factorOp.getValue()[0]).getValueAsDouble();
    double im = cast<FloatAttr>(factorOp.getValue()[1]).getValueAsDouble();
    if (std::abs(std::hypot(re, im) - 1.0) > 1e-9) {
      return scale.emitError("non-unit-modulus scale factor cannot be lowered to QCO");
    }
    qco::GPhaseOp::create(builder, loc, std::atan2(im, re));
    auto it = qubitMap.find(scale.getInput());
    if (it == qubitMap.end()) {
      return scale.emitError("input has no lowered qubits");
    }
    SmallVector<Value> qubits = it->second;
    qubitMap[scale.getResult()] = std::move(qubits);
    opsToErase.push_back(scale);
    return success();
  }
  if (auto exp = dyn_cast<hlep::ExpOp>(operation)) {
    return lowerExp(exp);
  }
  if (auto lin = dyn_cast<hlep::LinOp>(operation)) {
    LinLowering lowering(lin, builder, qubitMap);
    if (failed(lowering.run())) {
      return failure();
    }
    opsToErase.push_back(lin);
    return success();
  }
  if (auto call = dyn_cast<func::CallOp>(operation)) {
    return lowerCall(call);
  }
  if (auto ret = dyn_cast<func::ReturnOp>(operation)) {
    return lowerReturn(ret);
  }
  if (auto ifOp = dyn_cast<scf::IfOp>(operation)) {
    if (llvm::any_of(ifOp.getResultTypes(), isPrelimHLEPType)) {
      return ifOp.emitError("scf.if over linear values outside a prelimhlep.lin body is not yet supported by the "
                            "QCO lowering");
    }
    return success();
  }

  // Any other op touching PrelimHLEP values is unsupported.
  bool touchesPrelimHLEP = llvm::any_of(operation->getOperandTypes(), isPrelimHLEPType) ||
                           llvm::any_of(operation->getResultTypes(), isPrelimHLEPType);
  if (touchesPrelimHLEP) {
    return operation->emitError("op on PrelimHLEP values is not supported by the QCO lowering");
  }
  return success();
}

LogicalResult FunctionLowering::run() {
  auto it = newSignatures.find(fn);
  FunctionType newType = it == newSignatures.end() ? nullptr : it->second;

  if (fn.getBody().empty()) {
    if (newType) {
      fn.setType(newType);
      fn->removeAttr(kHaloAttrName);
    }
    return success();
  }

  if (newType && !fn.getBody().hasOneBlock()) {
    return fn.emitError("multi-block functions are not supported by the QCO lowering");
  }

  // Expand the entry block arguments: append the new arguments (in order)
  // and record the mapping; the old arguments are erased at the end.
  unsigned numOldArgs = 0;
  if (newType) {
    Block& entry = fn.getBody().front();
    numOldArgs = entry.getNumArguments();
    for (BlockArgument arg : llvm::to_vector(entry.getArguments())) {
      if (auto width = getLinWidth(arg.getType())) {
        SmallVector<Value> qubits;
        for (int64_t j = 0; j < *width; ++j) {
          qubits.push_back(entry.addArgument(qubitType(), arg.getLoc()));
        }
        qubitMap[arg] = std::move(qubits);
      } else if (isa<hlep::UnitType>(arg.getType())) {
        qubitMap[arg] = {};
      } else if (isPrelimHLEPType(arg.getType())) {
        return fn.emitError("argument type cannot be lowered to QCO");
      } else {
        entry.addArgument(arg.getType(), arg.getLoc());
        arg.replaceAllUsesWith(entry.getArguments().back());
      }
    }
  }

  // Process ops in program order. Halo functions are single-block; for
  // classical functions the walk only ever matches position-independent
  // ops (unit values and calls).
  SmallVector<Operation*> worklist;
  fn.walk<WalkOrder::PreOrder>([&](Operation* operation) {
    if (operation == fn.getOperation()) {
      return WalkResult::advance();
    }
    worklist.push_back(operation);
    // The pattern library interprets lin bodies itself.
    return isa<hlep::LinOp>(operation) ? WalkResult::skip() : WalkResult::advance();
  });
  for (Operation* operation : worklist) {
    if (failed(lowerOp(operation))) {
      return failure();
    }
  }

  for (Operation* operation : llvm::reverse(opsToErase)) {
    operation->erase();
  }

  if (newType) {
    Block& entry = fn.getBody().front();
    BitVector eraseIndices(entry.getNumArguments());
    eraseIndices.set(0, numOldArgs);
    entry.eraseArguments(eraseIndices);
    fn.setType(newType);
    fn->removeAttr(kHaloAttrName);
  }
  return success();
}

//===----------------------------------------------------------------------===//
// Pass
//===----------------------------------------------------------------------===//

struct PrelimHLEPToQCO final : impl::PrelimHLEPToQCOBase<PrelimHLEPToQCO> {
  using PrelimHLEPToQCOBase::PrelimHLEPToQCOBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();

    // Precompute the converted signature of every function that needs one,
    // so calls can be rewritten in any order.
    DenseMap<Operation*, FunctionType> newSignatures;
    for (auto fn : module.getOps<func::FuncOp>()) {
      bool needsConversion = fn->hasAttr(kHaloAttrName) || llvm::any_of(fn.getArgumentTypes(), isPrelimHLEPType) ||
                             llvm::any_of(fn.getResultTypes(), isPrelimHLEPType);
      if (!needsConversion) {
        continue;
      }
      SmallVector<Type> inputs;
      SmallVector<Type> results;
      for (Type type : fn.getArgumentTypes()) {
        if (failed(expandType(type, inputs))) {
          fn.emitError("argument type cannot be lowered to QCO");
          return signalPassFailure();
        }
      }
      for (Type type : fn.getResultTypes()) {
        if (failed(expandType(type, results))) {
          fn.emitError("result type cannot be lowered to QCO");
          return signalPassFailure();
        }
      }
      newSignatures[fn] = FunctionType::get(&getContext(), inputs, results);
    }

    for (auto fn : llvm::make_early_inc_range(module.getOps<func::FuncOp>())) {
      FunctionLowering lowering(fn, newSignatures);
      if (failed(lowering.run())) {
        return signalPassFailure();
      }
    }
  }
};

} // namespace
} // namespace qcc
