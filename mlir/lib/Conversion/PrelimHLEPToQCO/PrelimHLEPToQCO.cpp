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
// `prelimhlep.lin` ops must be in normal form (tagged with a shape; see
// `--prelim-hlep-normalize-lin`): every shape maps onto one QCO op, so
// this pass only dispatches on the tag and never inspects a body.
//
//===----------------------------------------------------------------------===//

#include "qcc/Conversion/PrelimHLEPToQCO/PrelimHLEPToQCO.h"

#include "qcc/Dialect/PrelimHLEP/IR/LinShapes.h"
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

/// Per-function lowering state: maps every not-yet-erased PrelimHLEP-typed
/// SSA value to the list of qubit values (LSB first) it lowers to.
using QubitMap = DenseMap<Value, SmallVector<Value>>;

/// Emits the QCO gate of a `phase`-shaped `lin` op on `qubit`: `qco.z` for
/// a factor of -1, `qco.p(angle)` otherwise.
Value emitPhaseGate(OpBuilder& builder, Location loc, hlep::LinOp phase, Value qubit) {
  auto [re, im] = hlep::getPhaseShapeFactor(phase);
  double angle = std::atan2(im, re);
  bool isMinusOne = std::abs(angle - M_PI) < 1e-9 || std::abs(angle + M_PI) < 1e-9;
  if (isMinusOne) {
    return qco::ZOp::create(builder, loc, qco::QubitType::get(builder.getContext()), qubit);
  }
  return qco::POp::create(builder, loc, qubit, angle);
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
  LogicalResult lowerLin(hlep::LinOp lin);
  LogicalResult lowerCall(func::CallOp call);
  LogicalResult lowerReturn(func::ReturnOp ret);

  /// Looks up the qubit expansion of `value`; classical values expand to
  /// themselves.
  LogicalResult expandValue(Value value, SmallVectorImpl<Value>& out);

  /// The single qubit a `!prelimhlep.lin<i1>` value lowers to.
  FailureOr<Value> qubitOf(Operation* user, Value value);

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

FailureOr<Value> FunctionLowering::qubitOf(Operation* user, Value value) {
  auto it = qubitMap.find(value);
  if (it == qubitMap.end() || it->second.size() != 1) {
    return user->emitError("operand has no lowered qubit");
  }
  return it->second.front();
}

/// Lowers one normal-form `lin` op. The shape verifier guarantees the
/// operand/result layout of every shape, so only the tag is inspected.
LogicalResult FunctionLowering::lowerLin(hlep::LinOp lin) {
  Location loc = lin.getLoc();
  std::optional<hlep::LinShape> shape = lin.getShape();
  if (!shape) {
    return lin.emitError("prelimhlep.lin is not in normal form; run --prelim-hlep-normalize-lin first");
  }
  opsToErase.push_back(lin);

  switch (*shape) {
  case hlep::LinShape::Alloc:
    qubitMap[lin.getResult(0)] = {qco::AllocOp::create(builder, loc)};
    return success();

  case hlep::LinShape::Split: {
    auto it = qubitMap.find(lin.getDelinearizedOperands()[0]);
    if (it == qubitMap.end()) {
      return lin.emitError("operand has no lowered qubits");
    }
    SmallVector<Value> qubits = it->second;
    for (auto [result, qubit] : llvm::zip_equal(lin.getResults(), qubits)) {
      qubitMap[result] = {qubit};
    }
    return success();
  }

  case hlep::LinShape::Join: {
    SmallVector<Value> qubits;
    for (Value operand : lin.getDelinearizedOperands()) {
      FailureOr<Value> qubit = qubitOf(lin, operand);
      if (failed(qubit)) {
        return failure();
      }
      qubits.push_back(*qubit);
    }
    qubitMap[lin.getResult(0)] = std::move(qubits);
    return success();
  }

  case hlep::LinShape::X: {
    FailureOr<Value> qubit = qubitOf(lin, lin.getDelinearizedOperands()[0]);
    if (failed(qubit)) {
      return failure();
    }
    qubitMap[lin.getResult(0)] = {qco::XOp::create(builder, loc, qubitType(), *qubit)};
    return success();
  }

  case hlep::LinShape::Measure:
  case hlep::LinShape::MeasureDrop: {
    FailureOr<Value> qubit = qubitOf(lin, lin.getDelinearizedOperands()[0]);
    if (failed(qubit)) {
      return failure();
    }
    auto measure = qco::MeasureOp::create(builder, loc, *qubit);
    if (*shape == hlep::LinShape::Measure) {
      qubitMap[lin.getResult(0)] = {measure.getQubitOut()};
      lin.getResult(1).replaceAllUsesWith(measure.getResult());
    } else {
      qco::SinkOp::create(builder, loc, measure.getQubitOut());
      lin.getResult(0).replaceAllUsesWith(measure.getResult());
    }
    return success();
  }

  case hlep::LinShape::Hadamard: {
    FailureOr<Value> qubit = qubitOf(lin, lin.getDelinearizedOperands()[0]);
    if (failed(qubit)) {
      return failure();
    }
    Value rotated = qco::HOp::create(builder, loc, qubitType(), *qubit);
    if (isa<hlep::YType>(cast<hlep::LinType>(lin.getResult(0).getType()).getElementType())) {
      rotated = qco::SOp::create(builder, loc, qubitType(), rotated);
    }
    qubitMap[lin.getResult(0)] = {rotated};
    return success();
  }

  case hlep::LinShape::Phase: {
    FailureOr<Value> qubit = qubitOf(lin, lin.getDelinearizedOperands()[0]);
    if (failed(qubit)) {
      return failure();
    }
    qubitMap[lin.getResult(0)] = {emitPhaseGate(builder, loc, lin, *qubit)};
    return success();
  }

  case hlep::LinShape::Ctrl: {
    SmallVector<Value> controls;
    for (Value operand : lin.getDelinearizedOperands()) {
      FailureOr<Value> qubit = qubitOf(lin, operand);
      if (failed(qubit)) {
        return failure();
      }
      controls.push_back(*qubit);
    }
    FailureOr<Value> target = qubitOf(lin, hlep::getCtrlShapeTarget(lin));
    if (failed(target)) {
      return failure();
    }
    hlep::LinOp gate = hlep::getCtrlShapeGate(lin);
    auto ctrl =
        qco::CtrlOp::create(builder, loc, controls, ValueRange{*target}, [&](ValueRange targets) -> SmallVector<Value> {
          if (*gate.getShape() == hlep::LinShape::X) {
            return {qco::XOp::create(builder, loc, qubitType(), targets[0])};
          }
          return {emitPhaseGate(builder, loc, gate, targets[0])};
        });
    for (auto [result, control] : llvm::zip_equal(lin.getResults().drop_back(), ctrl.getControlsOut())) {
      qubitMap[result] = {control};
    }
    qubitMap[lin.getResults().back()] = {ctrl.getTargetsOut()[0]};
    return success();
  }
  }
  llvm_unreachable("unknown LinShape");
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
    return lowerLin(lin);
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
    // Normal-form lin bodies are consumed by the shape lowering.
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
