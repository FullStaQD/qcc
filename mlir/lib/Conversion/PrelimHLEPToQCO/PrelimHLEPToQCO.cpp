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
// `prelimhlep.lin` ops must have been peeled into `hlepgate` ops (see
// `--prelim-hlep-lin-to-gates`), each of which maps onto one QCO op (or
// none, for the rewiring ops).
//
//===----------------------------------------------------------------------===//

#include "qcc/Conversion/PrelimHLEPToQCO/PrelimHLEPToQCO.h"

#include "qcc/Dialect/HLEPGate/IR/HLEPGate.h"
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
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/APInt.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <cmath>
#include <cstdint>
#include <optional>
#include <utility>
#include <variant>

namespace qcc {
using namespace mlir;
namespace hlep = qcc::prelimhlep;
namespace gate = qcc::hlepgate;

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

/// A gate angle: the constant itself if it is one, so that QCO can fold it
/// into the op.
std::variant<double, Value> getAngle(Value angle) {
  FloatAttr constant;
  if (matchPattern(angle, m_Constant(&constant))) {
    return constant.getValueAsDouble();
  }
  return angle;
}

/// Emits the uncontrolled QCO gate of `kind` on `qubit`.
Value emitGate(OpBuilder& builder, Location loc, gate::GateKind kind, ValueRange params, Value qubit) {
  Type qubitType = qco::QubitType::get(builder.getContext());
  switch (kind) {
  case gate::GateKind::X:
    return qco::XOp::create(builder, loc, qubitType, qubit);
  case gate::GateKind::Y:
    return qco::YOp::create(builder, loc, qubitType, qubit);
  case gate::GateKind::Z:
    return qco::ZOp::create(builder, loc, qubitType, qubit);
  case gate::GateKind::H:
    return qco::HOp::create(builder, loc, qubitType, qubit);
  case gate::GateKind::S:
    return qco::SOp::create(builder, loc, qubitType, qubit);
  case gate::GateKind::Sdg:
    return qco::SdgOp::create(builder, loc, qubitType, qubit);
  case gate::GateKind::T:
    return qco::TOp::create(builder, loc, qubitType, qubit);
  case gate::GateKind::Tdg:
    return qco::TdgOp::create(builder, loc, qubitType, qubit);
  case gate::GateKind::P:
    return qco::POp::create(builder, loc, qubit, getAngle(params[0]));
  case gate::GateKind::RX:
    return qco::RXOp::create(builder, loc, qubit, getAngle(params[0]));
  case gate::GateKind::RY:
    return qco::RYOp::create(builder, loc, qubit, getAngle(params[0]));
  case gate::GateKind::RZ:
    return qco::RZOp::create(builder, loc, qubit, getAngle(params[0]));
  }
  llvm_unreachable("unknown GateKind");
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
  LogicalResult lowerExp(hlep::ExpOp exp);
  LogicalResult lowerGateOp(Operation* operation);
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

/// Lowers one `hlepgate` op.
LogicalResult FunctionLowering::lowerGateOp(Operation* operation) {
  Location loc = operation->getLoc();
  opsToErase.push_back(operation);

  if (auto alloc = dyn_cast<gate::AllocOp>(operation)) {
    qubitMap[alloc.getResult()] = {qco::AllocOp::create(builder, loc)};
    return success();
  }

  if (auto split = dyn_cast<gate::SplitOp>(operation)) {
    auto it = qubitMap.find(split.getReg());
    if (it == qubitMap.end()) {
      return split.emitError("operand has no lowered qubits");
    }
    SmallVector<Value> qubits = it->second;
    for (auto [result, qubit] : llvm::zip_equal(split.getQubits(), qubits)) {
      qubitMap[result] = {qubit};
    }
    return success();
  }

  if (auto join = dyn_cast<gate::JoinOp>(operation)) {
    SmallVector<Value> qubits;
    for (Value operand : join.getQubits()) {
      FailureOr<Value> qubit = qubitOf(join, operand);
      if (failed(qubit)) {
        return failure();
      }
      qubits.push_back(*qubit);
    }
    qubitMap[join.getReg()] = std::move(qubits);
    return success();
  }

  if (auto measure = dyn_cast<gate::MeasureOp>(operation)) {
    FailureOr<Value> qubit = qubitOf(measure, measure.getQubit());
    if (failed(qubit)) {
      return failure();
    }
    auto lowered = qco::MeasureOp::create(builder, loc, *qubit);
    qubitMap[measure.getQubitOut()] = {lowered.getQubitOut()};
    measure.getOutcome().replaceAllUsesWith(lowered.getResult());
    return success();
  }

  if (auto sink = dyn_cast<gate::SinkOp>(operation)) {
    FailureOr<Value> qubit = qubitOf(sink, sink.getQubit());
    if (failed(qubit)) {
      return failure();
    }
    qco::SinkOp::create(builder, loc, *qubit);
    return success();
  }

  auto single = cast<gate::SingleOp>(operation);
  FailureOr<Value> target = qubitOf(single, single.getTarget());
  if (failed(target)) {
    return failure();
  }
  if (single.getControls().empty()) {
    qubitMap[single.getTargetOut()] = {emitGate(builder, loc, single.getKind(), single.getParams(), *target)};
    return success();
  }
  SmallVector<Value> controls;
  for (Value operand : single.getControls()) {
    FailureOr<Value> qubit = qubitOf(single, operand);
    if (failed(qubit)) {
      return failure();
    }
    controls.push_back(*qubit);
  }
  auto ctrl =
      qco::CtrlOp::create(builder, loc, controls, ValueRange{*target}, [&](ValueRange targets) -> SmallVector<Value> {
        return {emitGate(builder, loc, single.getKind(), single.getParams(), targets[0])};
      });
  for (auto [result, control] : llvm::zip_equal(single.getControlsOut(), ctrl.getControlsOut())) {
    qubitMap[result] = {control};
  }
  qubitMap[single.getTargetOut()] = {ctrl.getTargetsOut()[0]};
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
  if (isa<gate::HLEPGateDialect>(operation->getDialect())) {
    return lowerGateOp(operation);
  }
  if (isa<hlep::LinOp>(operation)) {
    return operation->emitError("prelimhlep.lin must be peeled into gates first; run --prelim-hlep-lin-to-gates");
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
    // A remaining lin op is reported as an error; its body is not visited.
    return isa<hlep::LinOp>(operation) ? WalkResult::skip() : WalkResult::advance();
  });
  for (Operation* operation : worklist) {
    if (failed(lowerOp(operation))) {
      return failure();
    }
  }

  // Gate angles that QCO folded into its ops as constants are dead now.
  SmallVector<Operation*> angleDefs;
  for (Operation* operation : opsToErase) {
    if (auto single = dyn_cast<gate::SingleOp>(operation)) {
      for (Value param : single.getParams()) {
        if (Operation* def = param.getDefiningOp(); def && def->hasTrait<OpTrait::ConstantLike>()) {
          angleDefs.push_back(def);
        }
      }
    }
  }
  for (Operation* operation : llvm::reverse(opsToErase)) {
    operation->erase();
  }
  for (Operation* def : angleDefs) {
    if (isOpTriviallyDead(def)) {
      def->erase();
    }
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
