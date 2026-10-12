// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// Lowers `prelimhlep.lin` ops to `hlepgate` ops by peeling gates out of them
// (see the pass description in Passes.td).
//
// Every peel replaces a `lin` op L by a gate G and a smaller `lin` op L' with
// L = L' . G (input side) or L = G . L' (output side). The gate is emitted
// next to L', and L's body is composed with the inverse of G, which is what
// makes the remaining op smaller. After every peel, the IR is valid and
// denotes the same program. The op is erased once nothing is left of it.
//
// Peels run in a fixed order, so the resulting circuit does not depend on
// the order in which a rewrite driver would visit ops:
//
//   1. Registers: multi-qubit operands are split, multi-qubit results joined,
//      so that every delinearized value is a single bit. Classical X-/Y-basis
//      results (constants, Hadamard-like conditionals) are evaluated to bits
//      and rotated into their basis after the op.
//   2. Independent parts: gates in the body acting on captured values only
//      are hoisted out, and carried values defined outside are forwarded.
//   3. Measurements: every input bit a classical `carrying` result depends
//      on is measured, and the result is rebuilt from the outcomes.
//   4. Conditionals, in body order: conditional phases and controlled
//      sub-circuits.
//   5. Wiring: constant output bits become allocations, negated input bits
//      `x` gates, and passed-through input bits are forwarded.
//   6. Leftovers: measured qubits the body no longer uses are sunk.
//
// Classical bit logic is interpreted by `LinBitEvaluator` rather than matched
// syntactically, so the inverse compositions a peel inserts into the body
// need not be folded away.
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/HLEPGate/IR/HLEPGate.h"
#include "qcc/Dialect/PrelimHLEP/IR/LinBitEvaluator.h"
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"
#include "qcc/Dialect/PrelimHLEP/Transforms/Passes.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Complex/IR/Complex.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Support/LLVM.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cmath>
#include <numbers>
#include <optional>
#include <utility>

namespace qcc {
using namespace mlir;
namespace hlep = qcc::prelimhlep;
namespace gate = qcc::hlepgate;

#define GEN_PASS_DEF_PRELIMHLEPLINTOGATES
#include "qcc/Dialect/PrelimHLEP/Transforms/Passes.h.inc"

namespace {

using hlep::Bits;
using hlep::BitValue;
using hlep::LinBitEvaluator;
using hlep::LinOp;

/// A conjunction of required input bit values, as (input bit, required
/// value) pairs sorted by input bit index.
using Predicate = SmallVector<std::pair<unsigned, bool>>;

/// Tolerance for recognizing unit-modulus factors and special angles.
constexpr double kTolerance = 1e-9;

/// For an `scf.if` of the conditional phase form `scf.if %p { scale %c, %v }
/// else { %w }`, the scale op of the then-branch.
hlep::ScaleOp getPhaseScale(scf::IfOp ifOp) {
  if (ifOp.getNumResults() != 1 || !ifOp.elseBlock() || isa<hlep::LinType>(ifOp.getResult(0).getType())) {
    return nullptr;
  }
  auto thenYield = cast<scf::YieldOp>(ifOp.thenBlock()->getTerminator());
  auto scale = thenYield.getOperand(0).getDefiningOp<hlep::ScaleOp>();
  return scale && scale->getBlock() == ifOp.thenBlock() ? scale : nullptr;
}

/// Whether `ifOp` yields a single classical X- or Y-basis value, which the
/// bit evaluator reads as a function of the condition.
bool isBasisConditional(scf::IfOp ifOp) {
  return ifOp.getNumResults() == 1 && ifOp.elseBlock() && isa<hlep::XType, hlep::YType>(ifOp.getResult(0).getType());
}

/// Where a linear value inside a controlled sub-circuit comes from: a value
/// captured from outside the branch, and the bit of it (or -1 for the whole
/// value).
using WireOrigin = std::pair<Value, int64_t>;

//===----------------------------------------------------------------------===//
// LinPeeler: peels one `lin` op into gates
//===----------------------------------------------------------------------===//

class LinPeeler {
public:
  explicit LinPeeler(LinOp op) : op(op), builder(op.getContext()), loc(op.getLoc()) {}

  LogicalResult run();

private:
  //===--------------------------------------------------------------------===//
  // Accessors and diagnostics
  //===--------------------------------------------------------------------===//

  Block& body() { return op.getBody().front(); }
  hlep::OutputOp output() { return cast<hlep::OutputOp>(body().getTerminator()); }
  Value operand(unsigned k) { return op.getDelinearizedOperands()[k]; }
  bool isCaptured(Value value) { return !op.getBody().isAncestor(value.getParentRegion()); }

  InFlightDiagnostic unrecognized(const Twine& what) {
    return op.emitError("unrecognized prelimhlep.lin body: ") << what;
  }

  /// Reports the evaluator's failure at the op it blames.
  LogicalResult evaluationFailure(LinBitEvaluator& evaluator) {
    Operation* culprit = evaluator.getFailureOp();
    if (culprit == op.getOperation()) {
      return unrecognized(evaluator.getFailureMessage());
    }
    return culprit->emitError(evaluator.getFailureMessage());
  }

  /// A bit evaluator for the current body that sees through conditional
  /// phases (their results are the passed-through bits).
  LinBitEvaluator makeEvaluator();

  void defineBasisConditional(LinBitEvaluator& evaluator, scf::IfOp ifOp);

  /// Evaluates the condition of an `scf.if` to a conjunction of required
  /// input bits.
  std::optional<Predicate> evalPredicate(LinBitEvaluator& evaluator, Value cond);

  /// Whether any delinearized or classical carried result, or the condition
  /// of any conditional other than `exclude`, depends on input bit `k`.
  FailureOr<bool> dependsOnInput(unsigned k, Operation* exclude);

  //===--------------------------------------------------------------------===//
  // Rewriting primitives
  //===--------------------------------------------------------------------===//

  /// Moves the body into a new `lin` op with the same operands, terminated
  /// by `output (delinearized) carrying (auxiliary)`. `op` is left bodiless
  /// until `replaceWith` replaces it.
  LinOp rebuild(ArrayRef<Value> delinearized, ArrayRef<Value> auxiliary);

  /// Replaces `op` by `newOp`. `replacements` has one entry per result of
  /// `op`: the value replacing it, or null for results that carry over to
  /// the results of `newOp`, in order.
  void replaceWith(LinOp newOp, ArrayRef<Value> replacements);

  /// Removes input bit `k`, on which nothing in the body depends anymore.
  /// Remaining (dead) uses of the block argument see the constant `false`.
  void eraseInputBit(unsigned k);

  /// Erases trivially dead ops from the body.
  void eraseDeadOps();

  gate::SingleOp emitGate(gate::GateKind kind, ValueRange params, ValueRange controls, Value target) {
    return gate::SingleOp::create(builder, loc, kind, params, controls, target);
  }
  Value emitGate(gate::GateKind kind, Value target) { return emitGate(kind, {}, {}, target).getTargetOut(); }

  /// Applies `x` (outside the op) to every predicate bit whose required
  /// value is 0 and returns the control qubits in predicate order; undone by
  /// `undoPolarityConjugation`, which feeds the controls back into the op.
  SmallVector<Value> applyPolarityConjugation(const Predicate& predicate);
  void undoPolarityConjugation(const Predicate& predicate, ValueRange controlsOut);

  //===--------------------------------------------------------------------===//
  // Peels
  //===--------------------------------------------------------------------===//

  LogicalResult splitRegisters();
  LogicalResult joinRegisters();
  void hoistIndependentOps();
  void forwardCapturedCarries();
  LogicalResult peelMeasurements();
  LogicalResult peelConditional(scf::IfOp ifOp);
  LogicalResult peelConditionalPhase(scf::IfOp ifOp, const Predicate& predicate);
  LogicalResult peelControlledCircuit(scf::IfOp ifOp, const Predicate& predicate);
  LogicalResult peelWiring();
  LogicalResult peelLeftovers();

  LinOp op;
  OpBuilder builder;
  Location loc;
};

//===----------------------------------------------------------------------===//
// Evaluation
//===----------------------------------------------------------------------===//

LinBitEvaluator LinPeeler::makeEvaluator() {
  LinBitEvaluator evaluator(op);
  for (auto ifOp : body().getOps<scf::IfOp>()) {
    if (isBasisConditional(ifOp)) {
      defineBasisConditional(evaluator, ifOp);
      continue;
    }
    if (!getPhaseScale(ifOp)) {
      continue;
    }
    auto elseYield = cast<scf::YieldOp>(ifOp.elseBlock()->getTerminator());
    if (std::optional<Bits> bits = evaluator.evaluate(elseYield.getOperand(0))) {
      evaluator.define(ifOp.getResult(0), *bits);
    }
  }
  return evaluator;
}

/// Defines the result of a basis-conditional (`scf.if` yielding a one-symbol
/// X- or Y-basis value) as the condition bit, negated if the else-branch
/// yields the first symbol. Does nothing for branches that are not two
/// different constants.
void LinPeeler::defineBasisConditional(LinBitEvaluator& evaluator, scf::IfOp ifOp) {
  auto thenYield = cast<scf::YieldOp>(ifOp.thenBlock()->getTerminator());
  auto elseYield = cast<scf::YieldOp>(ifOp.elseBlock()->getTerminator());
  std::optional<Bits> thenBits = evaluator.evaluate(thenYield.getOperand(0));
  std::optional<Bits> elseBits = evaluator.evaluate(elseYield.getOperand(0));
  if (!thenBits || !elseBits || !thenBits->front().isConstant() || !elseBits->front().isConstant() ||
      thenBits->front() == elseBits->front()) {
    return;
  }
  std::optional<Predicate> predicate = evalPredicate(evaluator, ifOp.getCondition());
  if (!predicate || predicate->size() != 1) {
    return;
  }
  // The condition holds iff the input bit equals `required`.
  auto [input, required] = predicate->front();
  bool thenBit = thenBits->front().flag;
  evaluator.define(ifOp.getResult(0), {BitValue::makeInput(input, required == thenBit ? false : true)});
}

std::optional<Predicate> LinPeeler::evalPredicate(LinBitEvaluator& evaluator, Value cond) {
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
      (void)evaluationFailure(evaluator);
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
      (void)evaluationFailure(evaluator);
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

FailureOr<bool> LinPeeler::dependsOnInput(unsigned k, Operation* exclude) {
  LinBitEvaluator evaluator = makeEvaluator();
  auto dependsOn = [&](Value value) -> FailureOr<bool> {
    std::optional<Bits> bits = evaluator.evaluate(value);
    if (!bits) {
      return evaluationFailure(evaluator);
    }
    return llvm::any_of(*bits, [&](BitValue bit) { return bit.isInput() && bit.input == k; });
  };

  hlep::OutputOp out = output();
  for (Value value : out.getDelinearizedResults()) {
    FailureOr<bool> depends = dependsOn(value);
    if (failed(depends) || *depends) {
      return depends;
    }
  }
  for (Value value : out.getAuxiliaryResults()) {
    if (isa<hlep::LinType>(value.getType())) {
      continue;
    }
    FailureOr<bool> depends = dependsOn(value);
    if (failed(depends) || *depends) {
      return depends;
    }
  }
  for (auto ifOp : body().getOps<scf::IfOp>()) {
    if (ifOp == exclude) {
      continue;
    }
    std::optional<Predicate> predicate = evalPredicate(evaluator, ifOp.getCondition());
    if (!predicate) {
      return failure();
    }
    if (llvm::any_of(*predicate, [&](const auto& pair) { return pair.first == k; })) {
      return true;
    }
  }
  return false;
}

//===----------------------------------------------------------------------===//
// Rewriting primitives
//===----------------------------------------------------------------------===//

LinOp LinPeeler::rebuild(ArrayRef<Value> delinearized, ArrayRef<Value> auxiliary) {
  SmallVector<Type> resultTypes;
  for (Value value : delinearized) {
    resultTypes.push_back(hlep::LinType::get(op.getContext(), value.getType()));
  }
  for (Value value : auxiliary) {
    resultTypes.push_back(value.getType());
  }

  builder.setInsertionPoint(op);
  auto newOp = LinOp::create(builder, loc, resultTypes, op.getDelinearizedOperands());
  newOp.getBody().takeBody(op.getBody());
  Block& block = newOp.getBody().front();
  Operation* oldOutput = block.getTerminator();
  builder.setInsertionPointToEnd(&block);
  hlep::OutputOp::create(builder, loc, delinearized, auxiliary);
  oldOutput->erase();
  return newOp;
}

void LinPeeler::replaceWith(LinOp newOp, ArrayRef<Value> replacements) {
  unsigned next = 0;
  for (auto [result, replacement] : llvm::zip_equal(op.getResults(), replacements)) {
    result.replaceAllUsesWith(replacement ? replacement : newOp.getResult(next++));
  }
  op.erase();
  op = newOp;
}

void LinPeeler::eraseInputBit(unsigned k) {
  BlockArgument arg = body().getArgument(k);
  if (!arg.use_empty()) {
    builder.setInsertionPointToStart(&body());
    Value zero = arith::ConstantOp::create(builder, loc, builder.getBoolAttr(false));
    arg.replaceAllUsesWith(zero);
  }
  body().eraseArgument(k);
  op->eraseOperand(k);
}

void LinPeeler::eraseDeadOps() {
  // Users come after the ops they use, so a single sweep in reverse order
  // also erases ops that only become dead through the sweep.
  SmallVector<Operation*> ops;
  for (Operation& nested : body().without_terminator()) {
    ops.push_back(&nested);
  }
  for (Operation* nested : llvm::reverse(ops)) {
    if (isOpTriviallyDead(nested)) {
      nested->erase();
    }
  }
}

SmallVector<Value> LinPeeler::applyPolarityConjugation(const Predicate& predicate) {
  builder.setInsertionPoint(op);
  SmallVector<Value> controls;
  for (auto [input, value] : predicate) {
    controls.push_back(value ? operand(input) : emitGate(gate::GateKind::X, operand(input)));
  }
  return controls;
}

void LinPeeler::undoPolarityConjugation(const Predicate& predicate, ValueRange controlsOut) {
  builder.setInsertionPoint(op);
  for (auto [pair, control] : llvm::zip_equal(predicate, controlsOut)) {
    auto [input, value] = pair;
    op->setOperand(input, value ? control : emitGate(gate::GateKind::X, control));
  }
}

//===----------------------------------------------------------------------===//
// 1. Registers
//===----------------------------------------------------------------------===//

/// Input side: `lin (%r : i<n> from %reg)` becomes `split %reg` feeding `n`
/// single-bit operands, from which the body reassembles `%r`.
LogicalResult LinPeeler::splitRegisters() {
  Type bitType = builder.getI1Type();
  for (unsigned k = 0; k < op.getDelinearizedOperands().size(); ++k) {
    std::optional<unsigned> width = gate::getRegisterWidth(operand(k).getType());
    if (!width || *width == 0) {
      return unrecognized("delinearized operand of type ") << operand(k).getType() << " is not a qubit register";
    }
    if (*width == 1) {
      continue;
    }

    builder.setInsertionPoint(op);
    auto split = gate::SplitOp::create(builder, loc, operand(k));

    BlockArgument oldArg = body().getArgument(k);
    SmallVector<Value> bits;
    for (unsigned j = 0; j < *width; ++j) {
      bits.push_back(body().insertArgument(k + 1 + j, bitType, loc));
    }
    builder.setInsertionPointToStart(&body());
    Type intType = oldArg.getType();
    Value accumulated = arith::ExtUIOp::create(builder, loc, intType, bits[0]);
    for (unsigned j = 1; j < *width; ++j) {
      Value extended = arith::ExtUIOp::create(builder, loc, intType, bits[j]);
      Value amount = arith::ConstantOp::create(builder, loc, builder.getIntegerAttr(intType, j));
      Value shifted = arith::ShLIOp::create(builder, loc, extended, amount);
      accumulated = arith::OrIOp::create(builder, loc, accumulated, shifted);
    }
    oldArg.replaceAllUsesWith(accumulated);
    body().eraseArgument(k);

    op->eraseOperand(k);
    op->insertOperands(k, split.getResults());
    k += *width - 1;
  }
  return success();
}

/// Output side: a delinearized `i<n>` result becomes `n` single-bit results
/// joined after the op. A classical X- or Y-basis result `x<n>` / `y<n>` is
/// evaluated to its bits, which the op returns as qubits in the
/// computational basis; they are rotated into the basis (`h`, and `s` for
/// Y) after the op, joined, and relabeled by a basis change.
LogicalResult LinPeeler::joinRegisters() {
  hlep::OutputOp out = output();
  bool anyRewrite = false;
  for (Value value : out.getDelinearizedResults()) {
    auto basisWidth = [&]() -> std::optional<unsigned> {
      if (auto intType = dyn_cast<IntegerType>(value.getType())) {
        return intType.getWidth();
      }
      if (auto xType = dyn_cast<hlep::XType>(value.getType())) {
        return xType.getSize();
      }
      if (auto yType = dyn_cast<hlep::YType>(value.getType())) {
        return yType.getSize();
      }
      return std::nullopt;
    }();
    if (!basisWidth || *basisWidth == 0) {
      return unrecognized("delinearized result of type ") << value.getType() << " is not a qubit register";
    }
    anyRewrite |= *basisWidth > 1 || !isa<IntegerType>(value.getType());
  }
  if (!anyRewrite) {
    return success();
  }

  LinBitEvaluator evaluator = makeEvaluator();
  auto bitValue = [&](BitValue bit) -> Value {
    if (bit.isConstant()) {
      return arith::ConstantOp::create(builder, loc, builder.getBoolAttr(bit.flag));
    }
    Value value = body().getArgument(bit.input);
    if (bit.flag) {
      Value one = arith::ConstantOp::create(builder, loc, builder.getBoolAttr(true));
      value = arith::XOrIOp::create(builder, loc, value, one);
    }
    return value;
  };

  builder.setInsertionPoint(out);
  SmallVector<Value> delinearized;
  SmallVector<unsigned> widths;
  for (Value value : out.getDelinearizedResults()) {
    if (isa<hlep::XType, hlep::YType>(value.getType())) {
      std::optional<Bits> bits = evaluator.evaluate(value);
      if (!bits) {
        return evaluationFailure(evaluator);
      }
      widths.push_back(bits->size());
      for (BitValue bit : *bits) {
        delinearized.push_back(bitValue(bit));
      }
      continue;
    }
    unsigned width = value.getType().getIntOrFloatBitWidth();
    widths.push_back(width);
    if (width == 1) {
      delinearized.push_back(value);
      continue;
    }
    for (unsigned j = 0; j < width; ++j) {
      Value shifted = value;
      if (j > 0) {
        Value amount = arith::ConstantOp::create(builder, loc, builder.getIntegerAttr(value.getType(), j));
        shifted = arith::ShRUIOp::create(builder, loc, value, amount);
      }
      delinearized.push_back(arith::TruncIOp::create(builder, loc, builder.getI1Type(), shifted));
    }
  }
  SmallVector<Value> auxiliary(out.getAuxiliaryResults());
  SmallVector<Type> basisTypes(llvm::map_range(out.getDelinearizedResults(), [](Value v) { return v.getType(); }));
  LinOp newOp = rebuild(delinearized, auxiliary);

  builder.setInsertionPointAfter(newOp);
  SmallVector<Value> replacements;
  unsigned next = 0;
  for (auto [index, width] : llvm::enumerate(widths)) {
    bool isBasis = isa<hlep::XType, hlep::YType>(basisTypes[index]);
    SmallVector<Value> qubits(newOp.getResults().slice(next, width));
    next += width;
    if (isBasis) {
      for (Value& qubit : qubits) {
        qubit = emitGate(gate::GateKind::H, qubit);
        if (isa<hlep::YType>(basisTypes[index])) {
          qubit = emitGate(gate::GateKind::S, qubit);
        }
      }
    }
    if (width == 1 && !isBasis) {
      replacements.push_back(qubits.front());
      continue;
    }
    Value joined = qubits.front();
    if (width > 1) {
      Type registerType = hlep::LinType::get(op.getContext(), builder.getIntegerType(width));
      joined = gate::JoinOp::create(builder, loc, registerType, qubits);
    }
    if (isBasis) {
      joined = hlep::BaseChangeOp::create(builder, loc, op.getResult(index).getType(), joined);
    }
    replacements.push_back(joined);
  }
  for (unsigned k = 0; k < auxiliary.size(); ++k) {
    replacements.push_back(newOp.getResult(next++));
  }
  replaceWith(newOp, replacements);
  eraseDeadOps();
  return success();
}

//===----------------------------------------------------------------------===//
// 2. Independent parts
//===----------------------------------------------------------------------===//

/// Gates in the body that act on captured values only act on the right
/// tensor factor; they commute with the linearized part and are hoisted out
/// of the op, along with the constants they need.
void LinPeeler::hoistIndependentOps() {
  auto isConstant = [](Value value) {
    Operation* def = value.getDefiningOp();
    return def != nullptr && def->hasTrait<OpTrait::ConstantLike>();
  };
  for (Operation& nested : llvm::make_early_inc_range(body().without_terminator())) {
    if (!isa<gate::HLEPGateDialect>(nested.getDialect()) && !isa<hlep::BaseChangeOp>(nested)) {
      continue;
    }
    if (!llvm::all_of(nested.getOperands(), [&](Value value) { return isCaptured(value) || isConstant(value); })) {
      continue;
    }
    for (Value value : nested.getOperands()) {
      if (!isCaptured(value)) {
        // A constant used elsewhere in the body stays there; the gate gets
        // its own copy.
        builder.setInsertionPoint(op);
        Operation* constant = value.getDefiningOp();
        nested.replaceUsesOfWith(value, builder.clone(*constant)->getResult(cast<OpResult>(value).getResultNumber()));
      }
    }
    nested.moveBefore(op);
  }
  eraseDeadOps();
}

/// A carried value defined outside the op does not depend on it and is
/// forwarded.
void LinPeeler::forwardCapturedCarries() {
  hlep::OutputOp out = output();
  if (llvm::none_of(out.getAuxiliaryResults(), [&](Value value) { return isCaptured(value); })) {
    return;
  }
  SmallVector<Value> delinearized(out.getDelinearizedResults());
  SmallVector<Value> auxiliary;
  SmallVector<Value> replacements(delinearized.size());
  for (Value value : out.getAuxiliaryResults()) {
    if (isCaptured(value)) {
      replacements.push_back(value);
    } else {
      replacements.push_back(nullptr);
      auxiliary.push_back(value);
    }
  }
  replaceWith(rebuild(delinearized, auxiliary), replacements);
}

//===----------------------------------------------------------------------===//
// 3. Measurements
//===----------------------------------------------------------------------===//

/// Every input bit a classical carried result depends on is measured before
/// the op, keeping the qubit, and the result is rebuilt from the outcomes.
/// Keeping the outcome is what makes this legitimate: within the world of
/// outcome `m`, the input bit equals `m`.
LogicalResult LinPeeler::peelMeasurements() {
  hlep::OutputOp out = output();
  auto isClassical = [](Value value) { return !isa<hlep::LinType>(value.getType()); };
  if (llvm::none_of(out.getAuxiliaryResults(), isClassical)) {
    return success();
  }

  LinBitEvaluator evaluator = makeEvaluator();
  SmallVector<Bits> auxBits;
  for (Value value : out.getAuxiliaryResults()) {
    if (!isClassical(value)) {
      continue;
    }
    std::optional<Bits> bits = evaluator.evaluate(value);
    if (!bits) {
      return evaluationFailure(evaluator);
    }
    auxBits.push_back(std::move(*bits));
  }

  builder.setInsertionPoint(op);
  DenseMap<unsigned, Value> outcomes;
  for (const Bits& bits : auxBits) {
    for (BitValue bit : bits) {
      if (bit.isConstant() || outcomes.contains(bit.input)) {
        continue;
      }
      auto measure = gate::MeasureOp::create(builder, loc, operand(bit.input));
      op->setOperand(bit.input, measure.getQubitOut());
      outcomes[bit.input] = measure.getOutcome();
    }
  }

  // Rebuild the classical values from the outcomes.
  auto bitValue = [&](BitValue bit) -> Value {
    if (bit.isConstant()) {
      return arith::ConstantOp::create(builder, loc, builder.getBoolAttr(bit.flag));
    }
    Value value = outcomes[bit.input];
    if (bit.flag) {
      Value one = arith::ConstantOp::create(builder, loc, builder.getBoolAttr(true));
      value = arith::XOrIOp::create(builder, loc, value, one);
    }
    return value;
  };
  auto buildValue = [&](const Bits& bits, Type type) -> Value {
    if (bits.size() == 1) {
      return bitValue(bits.front());
    }
    uint64_t constantPart = 0;
    for (auto [j, bit] : llvm::enumerate(bits)) {
      if (bit.isConstant() && bit.flag) {
        constantPart |= uint64_t(1) << j;
      }
    }
    Value accumulated = arith::ConstantOp::create(builder, loc, builder.getIntegerAttr(type, constantPart));
    for (auto [j, bit] : llvm::enumerate(bits)) {
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
  };

  SmallVector<Value> delinearized(out.getDelinearizedResults());
  SmallVector<Value> auxiliary;
  SmallVector<Value> replacements(delinearized.size());
  unsigned nextBits = 0;
  for (Value value : out.getAuxiliaryResults()) {
    if (isClassical(value)) {
      replacements.push_back(buildValue(auxBits[nextBits++], value.getType()));
    } else {
      replacements.push_back(nullptr);
      auxiliary.push_back(value);
    }
  }
  replaceWith(rebuild(delinearized, auxiliary), replacements);
  return success();
}

//===----------------------------------------------------------------------===//
// 4. Conditionals
//===----------------------------------------------------------------------===//

LogicalResult LinPeeler::peelConditional(scf::IfOp ifOp) {
  if (!ifOp.elseBlock()) {
    return unrecognized("conditional without an else-branch");
  }
  LinBitEvaluator evaluator = makeEvaluator();
  std::optional<Predicate> predicate = evalPredicate(evaluator, ifOp.getCondition());
  if (!predicate) {
    return failure();
  }
  if (llvm::none_of(ifOp.getResultTypes(), [](Type type) { return isa<hlep::LinType>(type); })) {
    return peelConditionalPhase(ifOp, *predicate);
  }
  return peelControlledCircuit(ifOp, *predicate);
}

/// Conditional phase: `scf.if %pred { scale by constant c } else
/// { passthrough }` is diagonal in the input bits. It becomes a `z` or `p`
/// on the last predicate bit, controlled by the others, with X-conjugation
/// of the bits required to be 0; the body keeps the passed-through bits.
LogicalResult LinPeeler::peelConditionalPhase(scf::IfOp ifOp, const Predicate& predicate) {
  hlep::ScaleOp scale = getPhaseScale(ifOp);
  if (!scale) {
    return unrecognized("expected a scale in the conditional branch");
  }
  auto factorOp = scale.getFactor().getDefiningOp<complex::ConstantOp>();
  if (!factorOp) {
    return scale.emitError("non-constant scale factor inside prelimhlep.lin body");
  }
  double re = cast<FloatAttr>(factorOp.getValue()[0]).getValueAsDouble();
  double im = cast<FloatAttr>(factorOp.getValue()[1]).getValueAsDouble();
  if (std::abs(std::hypot(re, im) - 1.0) > kTolerance) {
    return scale.emitError("non-unit-modulus scale factor is not a unitary operation");
  }

  Value passthrough = cast<scf::YieldOp>(ifOp.elseBlock()->getTerminator()).getOperand(0);
  if (ifOp->isAncestor(passthrough.getParentRegion()->getParentOp())) {
    return unrecognized("conditional phase computes the passed-through value in a branch");
  }
  LinBitEvaluator evaluator = makeEvaluator();
  std::optional<Bits> scaledBits = evaluator.evaluate(scale.getInput());
  std::optional<Bits> passthroughBits = evaluator.evaluate(passthrough);
  if (!scaledBits || !passthroughBits) {
    return evaluationFailure(evaluator);
  }
  if (*scaledBits != *passthroughBits) {
    return unrecognized("conditional branches disagree on the passed-through bits");
  }

  double angle = std::atan2(im, re);
  if (std::abs(angle) > kTolerance) {
    SmallVector<Value> controls = applyPolarityConjugation(predicate);
    Value target = controls.pop_back_val();
    gate::SingleOp phase;
    if (std::abs(std::abs(angle) - std::numbers::pi) < kTolerance) {
      phase = emitGate(gate::GateKind::Z, {}, controls, target);
    } else {
      Value angleValue = arith::ConstantOp::create(builder, loc, builder.getF64FloatAttr(angle));
      phase = emitGate(gate::GateKind::P, angleValue, controls, target);
    }
    SmallVector<Value> controlsOut(phase.getControlsOut());
    controlsOut.push_back(phase.getTargetOut());
    undoPolarityConjugation(predicate, controlsOut);
  }

  ifOp.getResult(0).replaceAllUsesWith(passthrough);
  ifOp.erase();
  return success();
}

/// Controlled sub-circuit: `scf.if %pred` applying gates to captured linear
/// values in the then-branch and passing them through in the else-branch.
/// The gates are emitted before the op, with the predicate bits prepended
/// to their controls (X-conjugated where required to be 0); rewiring ops
/// commute with control and are emitted as they are.
LogicalResult LinPeeler::peelControlledCircuit(scf::IfOp ifOp, const Predicate& predicate) {
  Block* thenBlock = ifOp.thenBlock();
  auto thenYield = cast<scf::YieldOp>(thenBlock->getTerminator());
  auto elseYield = cast<scf::YieldOp>(ifOp.elseBlock()->getTerminator());
  if (&ifOp.elseBlock()->front() != elseYield.getOperation() ||
      !llvm::all_of(elseYield.getOperands(), [&](Value value) { return isCaptured(value); })) {
    return unrecognized("conditional branches do not pass through captured linear values");
  }

  // Check the branch, and that every yielded value continues the wire the
  // else-branch passes through (otherwise the branch would permute wires,
  // which is not a gate under control).
  DenseMap<Value, WireOrigin> origins;
  auto originOf = [&](Value value) -> WireOrigin {
    auto it = origins.find(value);
    return it == origins.end() ? WireOrigin{value, -1} : it->second;
  };
  bool hasGates = false;
  for (Operation& nested : thenBlock->without_terminator()) {
    if (auto single = dyn_cast<gate::SingleOp>(nested)) {
      hasGates = true;
      for (auto [in, out] : llvm::zip_equal(single.getControls(), single.getControlsOut())) {
        origins[out] = originOf(in);
      }
      origins[single.getTargetOut()] = originOf(single.getTarget());
    } else if (auto split = dyn_cast<gate::SplitOp>(nested)) {
      WireOrigin origin = originOf(split.getReg());
      if (origin.second != -1) {
        return unrecognized("controlled sub-circuit splits a qubit");
      }
      for (auto [j, qubit] : llvm::enumerate(split.getQubits())) {
        origins[qubit] = {origin.first, static_cast<int64_t>(j)};
      }
    } else if (auto join = dyn_cast<gate::JoinOp>(nested)) {
      Value root = originOf(join.getQubits().front()).first;
      for (auto [j, qubit] : llvm::enumerate(join.getQubits())) {
        if (originOf(qubit) != WireOrigin{root, static_cast<int64_t>(j)}) {
          return unrecognized("controlled sub-circuit permutes its wires");
        }
      }
      origins[join.getReg()] = {root, -1};
    } else if (auto baseChange = dyn_cast<hlep::BaseChangeOp>(nested)) {
      origins[baseChange.getResult()] = originOf(baseChange.getInput());
    } else if (isa<gate::AllocOp, gate::MeasureOp, gate::SinkOp>(nested)) {
      return nested.emitError("'") << nested.getName() << "' is not a unitary gate and cannot be applied under a "
                                   << "condition";
    } else if (!nested.hasTrait<OpTrait::ConstantLike>()) {
      return nested.emitError("unrecognized op in a conditional branch of a prelimhlep.lin body; expected gates");
    }
  }
  for (auto [thenValue, elseValue] : llvm::zip_equal(thenYield.getOperands(), elseYield.getOperands())) {
    if (originOf(thenValue) != WireOrigin{elseValue, -1}) {
      return unrecognized("controlled sub-circuit permutes its wires");
    }
  }

  IRMapping mapping;
  SmallVector<Value> controls;
  if (hasGates) {
    controls = applyPolarityConjugation(predicate);
  }
  unsigned numControls = controls.size();
  builder.setInsertionPoint(op);
  for (Operation& nested : thenBlock->without_terminator()) {
    auto single = dyn_cast<gate::SingleOp>(nested);
    if (!single) {
      builder.clone(nested, mapping);
      continue;
    }
    SmallVector<Value> allControls = controls;
    for (Value inner : single.getControls()) {
      allControls.push_back(mapping.lookupOrDefault(inner));
    }
    SmallVector<Value> params;
    for (Value param : single.getParams()) {
      params.push_back(mapping.lookupOrDefault(param));
    }
    gate::SingleOp controlled =
        emitGate(single.getKind(), params, allControls, mapping.lookupOrDefault(single.getTarget()));
    controls.assign(controlled.getControlsOut().begin(), controlled.getControlsOut().begin() + numControls);
    for (auto [result, mapped] :
         llvm::zip_equal(single.getControlsOut(), controlled.getControlsOut().drop_front(numControls))) {
      mapping.map(result, mapped);
    }
    mapping.map(single.getTargetOut(), controlled.getTargetOut());
  }
  if (hasGates) {
    undoPolarityConjugation(predicate, controls);
  }

  for (auto [result, yielded] : llvm::zip_equal(ifOp.getResults(), thenYield.getOperands())) {
    result.replaceAllUsesWith(mapping.lookupOrDefault(yielded));
  }
  ifOp.erase();
  return success();
}

//===----------------------------------------------------------------------===//
// 5. Wiring
//===----------------------------------------------------------------------===//

/// Once only bit logic is left, each single-bit output is a constant (an
/// allocation, output side), a negated input bit (an `x` on the input,
/// input side), or an input bit (forwarded).
LogicalResult LinPeeler::peelWiring() {
  if (!output().getAuxiliaryResults().empty()) {
    return unrecognized("carried linear value is neither captured nor produced by a recognized conditional");
  }

  while (!output().getDelinearizedResults().empty()) {
    LinBitEvaluator evaluator = makeEvaluator();
    SmallVector<Value> delinearized(output().getDelinearizedResults());
    std::optional<Bits> bits = evaluator.evaluate(delinearized.front());
    if (!bits) {
      return evaluationFailure(evaluator);
    }
    BitValue bit = bits->front();

    if (bit.isInput() && bit.flag) {
      // L = L' . X on input bit k, where L' reads the bit negated.
      unsigned k = bit.input;
      builder.setInsertionPoint(op);
      op->setOperand(k, emitGate(gate::GateKind::X, operand(k)));
      BlockArgument arg = body().getArgument(k);
      builder.setInsertionPointToStart(&body());
      Value one = arith::ConstantOp::create(builder, loc, builder.getBoolAttr(true));
      auto negated = arith::XOrIOp::create(builder, loc, arg, one);
      arg.replaceAllUsesExcept(negated.getResult(), negated.getOperation());
      continue;
    }

    SmallVector<Value> replacements(op.getNumResults());
    std::optional<unsigned> forwardedInput;
    builder.setInsertionPoint(op);
    if (bit.isConstant()) {
      Value qubit = gate::AllocOp::create(builder, loc);
      replacements.front() = bit.flag ? emitGate(gate::GateKind::X, qubit) : qubit;
    } else {
      forwardedInput = bit.input;
      replacements.front() = operand(bit.input);
    }
    replaceWith(rebuild(ArrayRef<Value>(delinearized).drop_front(), {}), replacements);

    if (forwardedInput) {
      FailureOr<bool> depends = dependsOnInput(*forwardedInput, nullptr);
      if (failed(depends)) {
        return failure();
      }
      if (*depends) {
        return unrecognized("input bit used in more than one output");
      }
      eraseDeadOps();
      eraseInputBit(*forwardedInput);
    }
  }
  return success();
}

//===----------------------------------------------------------------------===//
// 6. Leftovers
//===----------------------------------------------------------------------===//

/// Whether `qubit` is in a computational basis state because it was
/// measured, possibly followed by gates that preserve basis states on it
/// (diagonal gates, or controlled gates it is a control of).
bool isMeasured(Value qubit) {
  while (true) {
    Operation* def = qubit.getDefiningOp();
    if (isa_and_nonnull<gate::MeasureOp>(def)) {
      return true;
    }
    auto single = dyn_cast_or_null<gate::SingleOp>(def);
    if (!single) {
      return false;
    }
    auto result = cast<OpResult>(qubit);
    if (result.getResultNumber() < single.getControlsOut().size()) {
      qubit = single.getControls()[result.getResultNumber()];
      continue;
    }
    switch (single.getKind()) {
    case gate::GateKind::Z:
    case gate::GateKind::S:
    case gate::GateKind::Sdg:
    case gate::GateKind::T:
    case gate::GateKind::Tdg:
    case gate::GateKind::P:
    case gate::GateKind::RZ:
      qubit = single.getTarget();
      continue;
    default:
      return false;
    }
  }
}

/// Input bits nothing depends on anymore are discarded. That is only
/// physical for measured qubits (measure, then forget): in the world of the
/// outcome, the qubit is in a basis state, and discarding it is the same as
/// the linearized discard. Measured qubits are sunk, right after the
/// measurement if nothing acted on them since.
LogicalResult LinPeeler::peelLeftovers() {
  eraseDeadOps();
  while (!op.getDelinearizedOperands().empty()) {
    Value qubit = operand(0);
    if (!isMeasured(qubit)) {
      return unrecognized("input bit is discarded without measurement");
    }
    if (auto measure = qubit.getDefiningOp<gate::MeasureOp>()) {
      builder.setInsertionPointAfter(measure);
    } else {
      // The outcome of measuring again is known; only the qubit is needed.
      builder.setInsertionPoint(op);
      qubit = gate::MeasureOp::create(builder, loc, qubit).getQubitOut();
    }
    gate::SinkOp::create(builder, loc, qubit);
    eraseInputBit(0);
  }
  eraseDeadOps();
  if (!body().without_terminator().empty()) {
    Operation& leftover = body().front();
    return leftover.emitError("op in prelimhlep.lin body could not be peeled into gates");
  }
  op.erase();
  return success();
}

LogicalResult LinPeeler::run() {
  if (failed(splitRegisters()) || failed(joinRegisters())) {
    return failure();
  }
  hoistIndependentOps();
  forwardCapturedCarries();
  if (failed(peelMeasurements())) {
    return failure();
  }
  while (true) {
    auto ifs = body().getOps<scf::IfOp>();
    if (ifs.empty()) {
      break;
    }
    if (failed(peelConditional(*ifs.begin()))) {
      return failure();
    }
    hoistIndependentOps();
    forwardCapturedCarries();
  }
  if (failed(peelWiring())) {
    return failure();
  }
  return peelLeftovers();
}

//===----------------------------------------------------------------------===//
// Pass
//===----------------------------------------------------------------------===//

struct PrelimHLEPLinToGates final : impl::PrelimHLEPLinToGatesBase<PrelimHLEPLinToGates> {
  using PrelimHLEPLinToGatesBase::PrelimHLEPLinToGatesBase;

  void runOnOperation() override {
    // Post-order: nested ops are peeled before the ops enclosing them, so
    // their gates are in place when the enclosing body is examined.
    SmallVector<LinOp> worklist;
    getOperation().walk([&](LinOp lin) { worklist.push_back(lin); });

    for (LinOp lin : worklist) {
      if (failed(LinPeeler(lin).run())) {
        return signalPassFailure();
      }
    }

    // Basis constants that canonicalization hoisted out of peeled bodies are
    // dead now.
    getOperation().walk([](hlep::ConstantOp constant) {
      if (constant->use_empty()) {
        constant.erase();
      }
    });

    // Fold the emitted gates only: this cancels split/join pairs of
    // registers passed through whole and adjacent inverse gates (e.g. from
    // X-conjugations of consecutive controlled gates).
    SmallVector<Operation*> gates;
    getOperation().walk([&](Operation* op) {
      if (isa<hlepgate::HLEPGateDialect>(op->getDialect())) {
        gates.push_back(op);
      }
    });
    GreedyRewriteConfig config;
    config.setStrictness(GreedyRewriteStrictness::ExistingAndNewOps);
    (void)applyOpPatternsGreedily(gates, FrozenRewritePatternSet(), config);
  }
};

} // namespace
} // namespace qcc
