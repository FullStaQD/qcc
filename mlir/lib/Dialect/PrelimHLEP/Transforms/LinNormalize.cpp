// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// Decomposes general `prelimhlep.lin` ops into chains of tagged normal-form
// shapes (see "Normal form of `lin` ops" in mlir/docs/Dialects/PrelimHLEP.md
// and the pass description in Passes.td).
//
// Every untagged `lin` op is interpreted symbolically: each classical
// integer value in the body becomes a vector of `BitValue`s over the
// flattened delinearized input bits, and at most one `scf.if` is handled
// structurally (conditional phase, basis-conditional constant, controlled
// sub-circuit). The interpretation is then re-emitted, in the op's parent
// block, as a chain of tagged `lin` ops over `!prelimhlep.lin<i1>` values:
// multi-qubit operands are `split` into single qubits lazily (only if some
// bit is touched individually), and multi-qubit results are `join`ed back.
//
// Ops are processed innermost first, so by the time an enclosing body is
// examined, the `lin` ops inside its `scf.if` branches are already tagged
// and can be re-emitted under control one gate at a time.
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/PrelimHLEP/IR/LinShapes.h"
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"
#include "qcc/Dialect/PrelimHLEP/Transforms/Passes.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Complex/IR/Complex.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Support/LLVM.h"

#include <cmath>

namespace qcc {
using namespace mlir;
namespace hlep = qcc::prelimhlep;

#define GEN_PASS_DEF_PRELIMHLEPNORMALIZELIN
#include "qcc/Dialect/PrelimHLEP/Transforms/Passes.h.inc"

namespace {

using hlep::Bits;
using hlep::BitValue;
using hlep::LinBitEvaluator;
using hlep::LinOp;
using hlep::LinShape;

/// A conjunction of required input bit values, as (input bit, required
/// value) pairs sorted by input bit index.
using Predicate = SmallVector<std::pair<unsigned, bool>>;

//===----------------------------------------------------------------------===//
// ShapeBuilder: emits the normal-form shapes
//===----------------------------------------------------------------------===//

/// Builds tagged `lin` ops at the builder's insertion point. The bodies
/// emitted here are the reference realization of each shape; the shape
/// verifier (LinShapes.cpp) accepts exactly these (up to the bit
/// evaluator's tolerance for equivalent arithmetic).
class ShapeBuilder {
public:
  ShapeBuilder(OpBuilder& builder, Location loc) : builder(builder), loc(loc) {}

  Type bitType() { return IntegerType::get(builder.getContext(), 1); }
  Type qubitType() { return hlep::LinType::get(builder.getContext(), bitType()); }

  /// `alloc () -> (lin<i1>)`: a fresh qubit in the |0> state.
  Value alloc() {
    return createLin(LinShape::Alloc, {}, {qubitType()},
                     [&](OpBuilder& b, ValueRange) {
                       Value zero = arith::ConstantOp::create(b, loc, b.getBoolAttr(false));
                       hlep::OutputOp::create(b, loc, ValueRange{zero}, ValueRange{});
                     })
        .getResult(0);
  }

  /// `split (i<n> from reg) -> (lin<i1> x n)`, least-significant bit first.
  SmallVector<Value> split(Value reg, unsigned width) {
    SmallVector<Type> resultTypes(width, qubitType());
    LinOp op = createLin(LinShape::Split, {reg}, resultTypes, [&](OpBuilder& b, ValueRange args) {
      Type intType = args[0].getType();
      SmallVector<Value> bits;
      for (unsigned j = 0; j < width; ++j) {
        Value shifted = args[0];
        if (j > 0) {
          Value amount = arith::ConstantOp::create(b, loc, b.getIntegerAttr(intType, j));
          shifted = arith::ShRUIOp::create(b, loc, args[0], amount);
        }
        bits.push_back(arith::TruncIOp::create(b, loc, bitType(), shifted));
      }
      hlep::OutputOp::create(b, loc, bits, ValueRange{});
    });
    return SmallVector<Value>(op.getResults());
  }

  /// `join (i1 from q_0, ..., i1 from q_{n-1}) -> (lin<i<n>>)`.
  Value join(ValueRange qubits) {
    unsigned width = qubits.size();
    Type intType = IntegerType::get(builder.getContext(), width);
    return createLin(LinShape::Join, qubits, {hlep::LinType::get(builder.getContext(), intType)},
                     [&](OpBuilder& b, ValueRange args) {
                       Value accumulated = arith::ExtUIOp::create(b, loc, intType, args[0]);
                       for (unsigned j = 1; j < width; ++j) {
                         Value extended = arith::ExtUIOp::create(b, loc, intType, args[j]);
                         Value amount = arith::ConstantOp::create(b, loc, b.getIntegerAttr(intType, j));
                         Value shifted = arith::ShLIOp::create(b, loc, extended, amount);
                         accumulated = arith::OrIOp::create(b, loc, accumulated, shifted);
                       }
                       hlep::OutputOp::create(b, loc, ValueRange{accumulated}, ValueRange{});
                     })
        .getResult(0);
  }

  /// `x (i1 from q) -> (lin<i1>)`: negation.
  Value x(Value qubit) {
    return createLin(LinShape::X, {qubit}, {qubitType()},
                     [&](OpBuilder& b, ValueRange args) {
                       Value one = arith::ConstantOp::create(b, loc, b.getBoolAttr(true));
                       Value negated = arith::XOrIOp::create(b, loc, args[0], one);
                       hlep::OutputOp::create(b, loc, ValueRange{negated}, ValueRange{});
                     })
        .getResult(0);
  }

  /// `measure (i1 from q) -> (lin<i1>, i1)`: the qubit and its outcome.
  std::pair<Value, Value> measure(Value qubit) {
    LinOp op = createLin(LinShape::Measure, {qubit}, {qubitType(), bitType()}, [&](OpBuilder& b, ValueRange args) {
      hlep::OutputOp::create(b, loc, ValueRange{args[0]}, ValueRange{args[0]});
    });
    return {op.getResult(0), op.getResult(1)};
  }

  /// `measure_drop (i1 from q) -> (i1)`: the outcome only.
  Value measureDrop(Value qubit) {
    return createLin(LinShape::MeasureDrop, {qubit}, {bitType()},
                     [&](OpBuilder& b, ValueRange args) {
                       hlep::OutputOp::create(b, loc, ValueRange{}, ValueRange{args[0]});
                     })
        .getResult(0);
  }

  /// `hadamard (i1 from q) -> (lin<x<1>> | lin<y<1>>)`: |0> to the first
  /// basis symbol, |1> to the second.
  Value hadamard(Value qubit, hlep::LinType resultType) {
    bool isY = isa<hlep::YType>(resultType.getElementType());
    StringRef first = isY ? "->" : "+";
    StringRef second = isY ? "<-" : "-";
    return createLin(LinShape::Hadamard, {qubit}, {resultType},
                     [&](OpBuilder& b, ValueRange args) {
                       auto ifOp = scf::IfOp::create(
                           b, loc, args[0],
                           [&](OpBuilder& thenBuilder, Location) {
                             Value constant = hlep::ConstantOp::create(thenBuilder, loc, resultType,
                                                                       thenBuilder.getStringAttr(second));
                             scf::YieldOp::create(thenBuilder, loc, constant);
                           },
                           [&](OpBuilder& elseBuilder, Location) {
                             Value constant = hlep::ConstantOp::create(elseBuilder, loc, resultType,
                                                                       elseBuilder.getStringAttr(first));
                             scf::YieldOp::create(elseBuilder, loc, constant);
                           });
                       hlep::OutputOp::create(b, loc, ValueRange{}, ValueRange{ifOp.getResult(0)});
                     })
        .getResult(0);
  }

  /// `phase (i1 from q) -> (lin<i1>)`: scales the |1> component by the
  /// constant unit-modulus `factor` (a `complex.constant` value attribute).
  Value phase(Value qubit, ArrayAttr factor) {
    return createLin(LinShape::Phase, {qubit}, {qubitType()},
                     [&](OpBuilder& b, ValueRange args) {
                       auto ifOp = scf::IfOp::create(
                           b, loc, args[0],
                           [&](OpBuilder& thenBuilder, Location) {
                             Value constant = complex::ConstantOp::create(
                                 thenBuilder, loc, ComplexType::get(thenBuilder.getF64Type()), factor);
                             Value scaled = hlep::ScaleOp::create(thenBuilder, loc, bitType(), constant, args[0]);
                             scf::YieldOp::create(thenBuilder, loc, scaled);
                           },
                           [&](OpBuilder& elseBuilder, Location) { scf::YieldOp::create(elseBuilder, loc, args[0]); });
                       hlep::OutputOp::create(b, loc, ValueRange{ifOp.getResult(0)}, ValueRange{});
                     })
        .getResult(0);
  }

  /// `ctrl (i1 from c_0, ..., i1 from c_{n-1}) -> (lin<i1> x n, lin<i1>)`:
  /// applies the gate `gate(builder, target)` emits to the captured
  /// `target` when all control bits are 1. Results are the controls in
  /// order, then the target.
  LinOp ctrl(ValueRange controls, Value target, function_ref<Value(OpBuilder&, Value)> gate) {
    SmallVector<Type> resultTypes(controls.size(), qubitType());
    resultTypes.push_back(target.getType());
    return createLin(LinShape::Ctrl, controls, resultTypes, [&](OpBuilder& b, ValueRange args) {
      Value condition = args[0];
      for (Value arg : args.drop_front()) {
        condition = arith::AndIOp::create(b, loc, condition, arg);
      }
      auto ifOp = scf::IfOp::create(
          b, loc, condition,
          [&](OpBuilder& thenBuilder, Location) {
            Value applied = gate(thenBuilder, target);
            scf::YieldOp::create(thenBuilder, loc, applied);
          },
          [&](OpBuilder& elseBuilder, Location) { scf::YieldOp::create(elseBuilder, loc, target); });
      hlep::OutputOp::create(b, loc, args, ValueRange{ifOp.getResult(0)});
    });
  }

private:
  /// Creates a tagged `lin` op whose body block (with one argument per
  /// delinearized operand) is populated by `body`, which must end with a
  /// `prelimhlep.output`.
  LinOp createLin(LinShape shape, ValueRange operands, TypeRange resultTypes,
                  function_ref<void(OpBuilder&, ValueRange)> body) {
    auto op = LinOp::create(builder, loc, resultTypes, operands, hlep::LinShapeAttr::get(builder.getContext(), shape));
    OpBuilder::InsertionGuard guard(builder);
    Block* block = builder.createBlock(&op.getBody());
    for (Value operand : operands) {
      block->addArgument(cast<hlep::LinType>(operand.getType()).getElementType(), loc);
    }
    body(builder, block->getArguments());
    return op;
  }

  OpBuilder& builder;
  Location loc;
};

//===----------------------------------------------------------------------===//
// LinNormalizer: decomposes one `lin` op
//===----------------------------------------------------------------------===//

class LinNormalizer {
public:
  LinNormalizer(LinOp op, OpBuilder& builder)
      : op(op), builder(builder), loc(op.getLoc()), shapes(builder, loc), evaluator(op) {}

  LogicalResult run();

private:
  InFlightDiagnostic unrecognized(const Twine& what) {
    return op.emitError("unrecognized prelimhlep.lin body: ") << what;
  }
  /// Reports the evaluator's failure at the op it blames.
  LogicalResult evaluationFailure() {
    Operation* culprit = evaluator.getFailureOp();
    if (culprit == op.getOperation()) {
      return unrecognized(evaluator.getFailureMessage());
    }
    return culprit->emitError(evaluator.getFailureMessage());
  }

  std::optional<Predicate> evalPredicate(Value cond);

  /// The `!prelimhlep.lin<i1>` value currently holding flattened input bit
  /// `k`, splitting its operand on first individual access.
  Value bit(unsigned k);
  void materialize(unsigned operandIndex);

  /// Whether `value` is defined outside the op being normalized (i.e.
  /// captured from the enclosing scope).
  bool isCaptured(Value value) { return !op.getBody().isAncestor(value.getParentRegion()); }

  LogicalResult classifyIf(scf::IfOp ifOp);
  LogicalResult lowerConditionalPhase(scf::IfOp ifOp, const Predicate& predicate);
  LogicalResult lowerConditionalConstant(scf::IfOp ifOp, const Predicate& predicate);
  LogicalResult lowerControlledCircuit(scf::IfOp ifOp, const Predicate& predicate);

  /// Applies `x` to every predicate qubit whose required value is 0 and
  /// returns the control qubits in predicate order (to be undone by
  /// `undoPolarityConjugation` on the ctrl outputs).
  SmallVector<Value> applyPolarityConjugation(const Predicate& predicate);
  void undoPolarityConjugation(const Predicate& predicate, ValueRange controlsOut);

  FailureOr<Value> emitDelinearizedResult(const Bits& bits);
  Value buildClassicalValue(const Bits& bits, Type type);

  LinOp op;
  OpBuilder& builder;
  Location loc;
  ShapeBuilder shapes;
  LinBitEvaluator evaluator;

  /// Flattened index of each operand's least-significant bit.
  SmallVector<unsigned> operandBase;
  /// Whether an operand has been split into individual qubits.
  SmallVector<bool> materialized;
  /// Current qubit value per flattened input bit (null until materialized).
  SmallVector<Value> current;
  /// Input bits consumed by an output (or a structural pattern).
  SmallVector<bool> used;
  /// Input bits that have been measured; `measuredBit[k]` is the i1 result.
  SmallVector<bool> measured;
  SmallVector<Value> measuredBit;
  /// Values in the enclosing scope standing in for linear values defined
  /// inside the body: hoisted tagged ops' results and structural `scf.if`
  /// results.
  IRMapping valueMap;
};

Value LinNormalizer::bit(unsigned k) {
  materialize(evaluator.getInputBitOrigin(k).first);
  return current[k];
}

void LinNormalizer::materialize(unsigned operandIndex) {
  if (materialized[operandIndex]) {
    return;
  }
  materialized[operandIndex] = true;
  Value operand = op.getDelinearizedOperands()[operandIndex];
  unsigned base = operandBase[operandIndex];
  unsigned width = cast<IntegerType>(cast<hlep::LinType>(operand.getType()).getElementType()).getWidth();
  if (width == 1) {
    current[base] = operand;
    return;
  }
  SmallVector<Value> qubits = shapes.split(operand, width);
  for (unsigned j = 0; j < width; ++j) {
    current[base + j] = qubits[j];
  }
}

std::optional<Predicate> LinNormalizer::evalPredicate(Value cond) {
  DenseMap<unsigned, bool> required;

  auto addRequirement = [&](unsigned input, bool value) -> bool {
    auto [it, inserted] = required.try_emplace(input, value);
    if (!inserted && it->second != value) {
      unrecognized("contradictory condition on an input bit");
      return false;
    }
    return true;
  };

  auto cmp = cond.getDefiningOp<arith::CmpIOp>();
  if (cmp && (cmp.getPredicate() == arith::CmpIPredicate::eq || cmp.getPredicate() == arith::CmpIPredicate::ne)) {
    std::optional<Bits> lhs = evaluator.evaluate(cmp.getLhs());
    std::optional<Bits> rhs = evaluator.evaluate(cmp.getRhs());
    if (!lhs || !rhs) {
      (void)evaluationFailure();
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
      unrecognized("comparison of two non-constant values");
      return std::nullopt;
    }
    bool negate = cmp.getPredicate() == arith::CmpIPredicate::ne;
    if (negate && inputSide.size() != 1) {
      unrecognized("multi-bit 'ne' comparison");
      return std::nullopt;
    }
    for (unsigned j = 0; j < inputSide.size(); ++j) {
      bool requiredValue = constantSide[j].flag != negate;
      BitValue bit = inputSide[j];
      if (bit.isConstant()) {
        if (bit.flag != requiredValue) {
          unrecognized("condition is constant");
          return std::nullopt;
        }
        continue;
      }
      if (!addRequirement(bit.input, requiredValue != bit.flag)) {
        return std::nullopt;
      }
    }
  } else {
    std::optional<Bits> bits = evaluator.evaluate(cond);
    if (!bits) {
      (void)evaluationFailure();
      return std::nullopt;
    }
    BitValue bit = (*bits)[0];
    if (bit.isConstant()) {
      unrecognized("condition is constant");
      return std::nullopt;
    }
    if (!addRequirement(bit.input, !bit.flag)) {
      return std::nullopt;
    }
  }

  if (required.empty()) {
    unrecognized("condition does not constrain any input bit");
    return std::nullopt;
  }
  Predicate predicate(required.begin(), required.end());
  llvm::sort(predicate, [](const auto& a, const auto& b) { return a.first < b.first; });
  return predicate;
}

SmallVector<Value> LinNormalizer::applyPolarityConjugation(const Predicate& predicate) {
  SmallVector<Value> controls;
  for (auto [input, value] : predicate) {
    if (!value) {
      current[input] = shapes.x(bit(input));
    }
    controls.push_back(bit(input));
  }
  return controls;
}

void LinNormalizer::undoPolarityConjugation(const Predicate& predicate, ValueRange controlsOut) {
  for (auto [pair, control] : llvm::zip_equal(predicate, controlsOut)) {
    auto [input, value] = pair;
    current[input] = value ? control : shapes.x(control);
  }
}

/// Conditional phase: `scf.if %pred { scale by constant c } else
/// { passthrough }` over classical bits. Becomes a `phase` on the last
/// predicate bit, controlled by the others, with X-conjugation on
/// negative-polarity bits.
LogicalResult LinNormalizer::lowerConditionalPhase(scf::IfOp ifOp, const Predicate& predicate) {
  if (ifOp.getNumResults() != 1) {
    return unrecognized("conditional phase with multiple results");
  }
  auto thenYield = cast<scf::YieldOp>(ifOp.thenBlock()->getTerminator());
  auto elseYield = cast<scf::YieldOp>(ifOp.elseBlock()->getTerminator());

  auto scale = thenYield.getOperand(0).getDefiningOp<hlep::ScaleOp>();
  if (!scale) {
    return unrecognized("expected a scale in the conditional branch");
  }
  auto factorOp = scale.getFactor().getDefiningOp<complex::ConstantOp>();
  if (!factorOp) {
    return scale.emitError("non-constant scale factor inside prelimhlep.lin body");
  }
  double re = cast<FloatAttr>(factorOp.getValue()[0]).getValueAsDouble();
  double im = cast<FloatAttr>(factorOp.getValue()[1]).getValueAsDouble();
  if (std::abs(std::hypot(re, im) - 1.0) > 1e-9) {
    return scale.emitError("non-unit-modulus scale factor is not a unitary operation");
  }

  std::optional<Bits> scaledBits = evaluator.evaluate(scale.getInput());
  std::optional<Bits> elseBits = evaluator.evaluate(elseYield.getOperand(0));
  if (!scaledBits || !elseBits) {
    return evaluationFailure();
  }
  if (*scaledBits != *elseBits) {
    return unrecognized("conditional branches disagree on the passed-through bits");
  }

  SmallVector<Value> controls = applyPolarityConjugation(predicate);
  Value target = controls.pop_back_val();
  SmallVector<Value> controlsOut;
  Value targetOut;
  if (controls.empty()) {
    targetOut = shapes.phase(target, factorOp.getValue());
  } else {
    LinOp ctrl = shapes.ctrl(controls, target,
                             [&](OpBuilder& b, Value t) { return ShapeBuilder(b, loc).phase(t, factorOp.getValue()); });
    controlsOut.append(ctrl.getResults().begin(), std::prev(ctrl.getResults().end()));
    targetOut = ctrl.getResults().back();
  }
  controlsOut.push_back(targetOut);
  undoPolarityConjugation(predicate, controlsOut);

  evaluator.define(ifOp.getResult(0), *elseBits);
  return success();
}

/// Basis-conditional constant (Hadamard family): `scf.if %bit` yielding a
/// one-symbol X- or Y-basis `prelimhlep.constant` in both branches. Becomes
/// a `hadamard` on the input qubit, preceded by `x` for the swapped symbol
/// mapping.
LogicalResult LinNormalizer::lowerConditionalConstant(scf::IfOp ifOp, const Predicate& predicate) {
  auto thenYield = cast<scf::YieldOp>(ifOp.thenBlock()->getTerminator());
  auto elseYield = cast<scf::YieldOp>(ifOp.elseBlock()->getTerminator());
  auto thenConstant = thenYield.getOperand(0).getDefiningOp<hlep::ConstantOp>();
  auto elseConstant = elseYield.getOperand(0).getDefiningOp<hlep::ConstantOp>();
  if (!thenConstant || !elseConstant || ifOp.getNumResults() != 1) {
    return unrecognized("conditional over linear values that is neither a controlled circuit nor a "
                        "basis-conditional constant");
  }
  if (predicate.size() != 1) {
    return unrecognized("basis-conditional constant with a multi-bit condition");
  }

  auto linType = cast<hlep::LinType>(ifOp.getResult(0).getType());
  bool isY = isa<hlep::YType>(linType.getElementType());
  if (thenConstant.getValue().size() != (isY ? 2U : 1U)) {
    return unrecognized("basis-conditional constant with more than one symbol");
  }
  // The second basis symbol is `-` for X and `<-` for Y.
  auto isSecondSymbol = [&](hlep::ConstantOp constant) { return constant.getValue().front() == '-' == !isY; };
  bool thenSecond = isSecondSymbol(thenConstant);
  bool elseSecond = isSecondSymbol(elseConstant);
  if (thenSecond == elseSecond) {
    return unrecognized("conditional constant does not depend on the condition");
  }

  auto [input, polarity] = predicate.front();
  // Symbol produced for input bit 0. `{0 -> first, 1 -> second}` is a plain
  // Hadamard; the swapped mapping is X followed by Hadamard.
  bool zeroSecond = polarity ? elseSecond : thenSecond;
  Value qubit = bit(input);
  if (zeroSecond) {
    qubit = shapes.x(qubit);
  }
  qubit = shapes.hadamard(qubit, linType);
  current[input] = qubit;
  used[input] = true;
  valueMap.map(ifOp.getResult(0), qubit);
  return success();
}

/// Controlled sub-circuit: `scf.if %pred` applying a sequence of tagged
/// `lin` ops to captured linear values in the then-branch and passing them
/// through in the else-branch. Wiring shapes are re-emitted as they are
/// (they commute with control); gates are re-emitted under `ctrl`, with the
/// predicate's controls prepended to any controls a nested `ctrl` already
/// has.
LogicalResult LinNormalizer::lowerControlledCircuit(scf::IfOp ifOp, const Predicate& predicate) {
  Block* thenBlock = ifOp.thenBlock();
  auto thenYield = cast<scf::YieldOp>(thenBlock->getTerminator());
  auto elseYield = cast<scf::YieldOp>(ifOp.elseBlock()->getTerminator());

  for (Value passthrough : elseYield.getOperands()) {
    if (!isCaptured(passthrough) && !valueMap.contains(passthrough)) {
      return unrecognized("conditional branches do not pass through captured linear values");
    }
  }
  for (Operation& nested : thenBlock->without_terminator()) {
    auto gate = dyn_cast<LinOp>(nested);
    if (!gate || !gate.getShape()) {
      return nested.emitError("unrecognized op in a conditional branch of a prelimhlep.lin body; expected a "
                              "normal-form prelimhlep.lin");
    }
  }

  IRMapping mapping = valueMap;
  SmallVector<Value> controls;
  if (!thenBlock->without_terminator().empty()) {
    controls = applyPolarityConjugation(predicate);
  }
  unsigned numControls = controls.size();

  for (Operation& nested : thenBlock->without_terminator()) {
    auto gate = cast<LinOp>(nested);
    switch (*gate.getShape()) {
    case LinShape::Split:
    case LinShape::Join:
      builder.clone(nested, mapping);
      break;
    case LinShape::X:
    case LinShape::Phase: {
      Value target = mapping.lookupOrDefault(gate.getDelinearizedOperands()[0]);
      LinOp ctrl = shapes.ctrl(controls, target, [&](OpBuilder& b, Value t) {
        IRMapping gateMapping;
        gateMapping.map(gate.getDelinearizedOperands()[0], t);
        return b.clone(*gate, gateMapping)->getResult(0);
      });
      controls.assign(ctrl.getResults().begin(), ctrl.getResults().begin() + numControls);
      mapping.map(gate.getResult(0), ctrl.getResults().back());
      break;
    }
    case LinShape::Ctrl: {
      SmallVector<Value> allControls = controls;
      for (Value innerControl : gate.getDelinearizedOperands()) {
        allControls.push_back(mapping.lookupOrDefault(innerControl));
      }
      Value target = mapping.lookupOrDefault(hlep::getCtrlShapeTarget(gate));
      LinOp innerGate = hlep::getCtrlShapeGate(gate);
      LinOp ctrl = shapes.ctrl(allControls, target, [&](OpBuilder& b, Value t) {
        IRMapping gateMapping;
        gateMapping.map(innerGate.getDelinearizedOperands()[0], t);
        return b.clone(*innerGate, gateMapping)->getResult(0);
      });
      controls.assign(ctrl.getResults().begin(), ctrl.getResults().begin() + numControls);
      for (auto [result, mapped] : llvm::zip_equal(gate.getResults(), ctrl.getResults().drop_front(numControls))) {
        mapping.map(result, mapped);
      }
      break;
    }
    case LinShape::Alloc:
    case LinShape::Measure:
    case LinShape::MeasureDrop:
    case LinShape::Hadamard:
      return nested.emitError("'") << hlep::stringifyLinShape(*gate.getShape())
                                   << "' is not a unitary gate and cannot be applied under a condition";
    }
  }

  for (auto [result, yielded] : llvm::zip_equal(ifOp.getResults(), thenYield.getOperands())) {
    valueMap.map(result, mapping.lookupOrDefault(yielded));
  }
  if (!thenBlock->without_terminator().empty()) {
    undoPolarityConjugation(predicate, controls);
  }
  return success();
}

LogicalResult LinNormalizer::classifyIf(scf::IfOp ifOp) {
  if (!ifOp.elseBlock()) {
    return unrecognized("conditional without an else-branch");
  }
  std::optional<Predicate> predicate = evalPredicate(ifOp.getCondition());
  if (!predicate) {
    return failure();
  }
  bool linearResults = llvm::any_of(ifOp.getResultTypes(), [](Type type) { return isa<hlep::LinType>(type); });
  if (!linearResults) {
    return lowerConditionalPhase(ifOp, *predicate);
  }
  auto thenYield = cast<scf::YieldOp>(ifOp.thenBlock()->getTerminator());
  if (thenYield.getNumOperands() == 1 && thenYield.getOperand(0).getDefiningOp<hlep::ConstantOp>()) {
    return lowerConditionalConstant(ifOp, *predicate);
  }
  return lowerControlledCircuit(ifOp, *predicate);
}

/// Materializes one delinearized output value from its symbolic bits:
/// constant bits become fresh allocations, input bits are (possibly negated
/// and) rewired, and multi-bit values are joined. An output that is exactly
/// an untouched operand reuses that operand without splitting it.
FailureOr<Value> LinNormalizer::emitDelinearizedResult(const Bits& bits) {
  unsigned width = bits.size();
  if (width > 0 && bits[0].isInput() && !bits[0].flag) {
    auto [operandIndex, firstBit] = evaluator.getInputBitOrigin(bits[0].input);
    Value operand = op.getDelinearizedOperands()[operandIndex];
    unsigned operandWidth = cast<IntegerType>(cast<hlep::LinType>(operand.getType()).getElementType()).getWidth();
    bool wholeOperand = firstBit == 0 && operandWidth == width && !materialized[operandIndex];
    for (unsigned j = 1; wholeOperand && j < width; ++j) {
      wholeOperand = bits[j].isInput() && !bits[j].flag && bits[j].input == bits[0].input + j;
    }
    if (wholeOperand) {
      return operand;
    }
  }

  SmallVector<Value> qubits;
  for (BitValue bitValue : bits) {
    Value qubit;
    if (bitValue.isConstant()) {
      qubit = shapes.alloc();
    } else {
      qubit = bit(bitValue.input);
    }
    if (bitValue.flag) {
      qubit = shapes.x(qubit);
    }
    qubits.push_back(qubit);
  }
  if (width == 1) {
    return qubits.front();
  }
  return shapes.join(qubits);
}

/// Rebuilds a classical integer value from measured/constant bits.
Value LinNormalizer::buildClassicalValue(const Bits& bits, Type type) {
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

LogicalResult LinNormalizer::run() {
  if (!evaluator.isValid()) {
    return unrecognized("non-integer delinearized value");
  }
  unsigned numBits = evaluator.getNumInputBits();
  unsigned numOperands = op.getDelinearizedOperands().size();
  for (unsigned k = 0; k < numBits; ++k) {
    auto [operandIndex, bitIndex] = evaluator.getInputBitOrigin(k);
    if (bitIndex == 0) {
      operandBase.resize(operandIndex + 1);
      operandBase[operandIndex] = k;
    }
  }
  operandBase.resize(numOperands);
  materialized.assign(numOperands, false);
  current.assign(numBits, Value());
  used.assign(numBits, false);
  measured.assign(numBits, false);
  measuredBit.assign(numBits, Value());

  builder.setInsertionPoint(op);
  Block& body = op.getBody().front();

  // Walk the body in order: tagged `lin` ops on captured values are hoisted
  // out unchanged (they act on the right tensor factor and commute with
  // everything here); at most one `scf.if` is handled structurally; the
  // remaining classical arithmetic is interpreted on demand.
  bool sawIf = false;
  for (Operation& nested : body.without_terminator()) {
    if (auto tagged = dyn_cast<LinOp>(nested)) {
      if (!tagged.getShape()) {
        return unrecognized("nested linearization outside a conditional");
      }
      builder.clone(nested, valueMap);
      continue;
    }
    if (auto ifOp = dyn_cast<scf::IfOp>(nested)) {
      if (sawIf) {
        return unrecognized("more than one conditional");
      }
      sawIf = true;
      if (failed(classifyIf(ifOp))) {
        return failure();
      }
    }
  }

  auto output = cast<hlep::OutputOp>(body.getTerminator());

  // Interpret every output before emitting anything, so that `used` is
  // final when measurements decide whether to keep their qubit.
  SmallVector<Bits> resultBits;
  for (Value delinearized : output.getDelinearizedResults()) {
    std::optional<Bits> bits = evaluator.evaluate(delinearized);
    if (!bits) {
      return evaluationFailure();
    }
    for (BitValue bitValue : *bits) {
      if (bitValue.isInput()) {
        if (used[bitValue.input]) {
          return unrecognized("input bit used in more than one output");
        }
        used[bitValue.input] = true;
      }
    }
    resultBits.push_back(std::move(*bits));
  }
  SmallVector<std::optional<Bits>> auxBits;
  for (Value aux : output.getAuxiliaryResults()) {
    if (isa<hlep::LinType>(aux.getType())) {
      auxBits.push_back(std::nullopt);
      continue;
    }
    std::optional<Bits> bits = evaluator.evaluate(aux);
    if (!bits) {
      return evaluationFailure();
    }
    auxBits.push_back(std::move(*bits));
  }

  // Measurements: every input bit a classical result depends on.
  for (const std::optional<Bits>& bits : auxBits) {
    if (!bits) {
      continue;
    }
    for (BitValue bitValue : *bits) {
      if (bitValue.isConstant() || measured[bitValue.input]) {
        continue;
      }
      unsigned k = bitValue.input;
      measured[k] = true;
      if (used[k]) {
        auto [qubit, outcome] = shapes.measure(bit(k));
        current[k] = qubit;
        measuredBit[k] = outcome;
      } else {
        measuredBit[k] = shapes.measureDrop(bit(k));
      }
    }
  }
  for (unsigned k = 0; k < numBits; ++k) {
    if (!used[k] && !measured[k]) {
      return unrecognized("input bit is discarded without measurement");
    }
  }

  // Results: re-linearized delinearized results, then auxiliary results.
  SmallVector<Value> newResults;
  for (const Bits& bits : resultBits) {
    FailureOr<Value> value = emitDelinearizedResult(bits);
    if (failed(value)) {
      return failure();
    }
    newResults.push_back(*value);
  }
  for (auto [aux, bits] : llvm::zip_equal(output.getAuxiliaryResults(), auxBits)) {
    if (bits) {
      newResults.push_back(buildClassicalValue(*bits, aux.getType()));
    } else if (valueMap.contains(aux) || isCaptured(aux)) {
      newResults.push_back(valueMap.lookupOrDefault(aux));
    } else {
      return unrecognized("carried linear value is neither captured nor produced by a recognized conditional");
    }
  }

  op.replaceAllUsesWith(newResults);
  op.erase();
  return success();
}

//===----------------------------------------------------------------------===//
// Pass
//===----------------------------------------------------------------------===//

struct PrelimHLEPNormalizeLin final : impl::PrelimHLEPNormalizeLinBase<PrelimHLEPNormalizeLin> {
  using PrelimHLEPNormalizeLinBase::PrelimHLEPNormalizeLinBase;

  void runOnOperation() override {
    // Post-order: nested ops are normalized before the ops enclosing them,
    // and the ops emitted for a nested body are tagged, so they are never
    // revisited.
    SmallVector<LinOp> worklist;
    getOperation().walk([&](LinOp lin) {
      if (!lin.getShape()) {
        worklist.push_back(lin);
      }
    });

    OpBuilder builder(&getContext());
    for (LinOp lin : worklist) {
      LinNormalizer normalizer(lin, builder);
      if (failed(normalizer.run())) {
        return signalPassFailure();
      }
    }
  }
};

} // namespace
} // namespace qcc
