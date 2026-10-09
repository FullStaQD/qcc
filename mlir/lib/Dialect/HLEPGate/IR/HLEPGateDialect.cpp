// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/HLEPGate/IR/HLEPGate.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h" // IWYU pragma: keep
#include "mlir/IR/OpImplementation.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/TypeSwitch.h" // IWYU pragma: keep

#include <optional>

using namespace mlir;
using namespace qcc::hlepgate;

#include "qcc/Dialect/HLEPGate/IR/HLEPGateDialect.cpp.inc"
#include "qcc/Dialect/HLEPGate/IR/HLEPGateEnums.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/HLEPGate/IR/HLEPGateAttrs.cpp.inc"

#define GET_OP_CLASSES
#include "qcc/Dialect/HLEPGate/IR/HLEPGateOps.cpp.inc"

void HLEPGateDialect::initialize() {
  addAttributes<
#define GET_ATTRDEF_LIST
#include "qcc/Dialect/HLEPGate/IR/HLEPGateAttrs.cpp.inc"
      >();

  addOperations<
#define GET_OP_LIST
#include "qcc/Dialect/HLEPGate/IR/HLEPGateOps.cpp.inc"
      >();
}

//===----------------------------------------------------------------------===//
// SingleOp
//===----------------------------------------------------------------------===//

unsigned SingleOp::getNumParams(GateKind kind) {
  switch (kind) {
  case GateKind::P:
  case GateKind::RX:
  case GateKind::RY:
  case GateKind::RZ:
    return 1;
  case GateKind::X:
  case GateKind::Y:
  case GateKind::Z:
  case GateKind::H:
  case GateKind::S:
  case GateKind::Sdg:
  case GateKind::T:
  case GateKind::Tdg:
    return 0;
  }
  llvm_unreachable("unknown GateKind");
}

LogicalResult SingleOp::inferReturnTypes(MLIRContext* context, std::optional<Location> /*location*/, Adaptor adaptor,
                                         SmallVectorImpl<Type>& inferredReturnTypes) {
  inferredReturnTypes.assign(adaptor.getControls().size() + 1, getQubitType(context));
  return success();
}

LogicalResult SingleOp::verify() {
  unsigned expected = getNumParams(getKind());
  if (getParams().size() != expected) {
    return emitOpError("expected ") << expected << " angle(s) for gate '" << stringifyGateKind(getKind()) << "', got "
                                    << getParams().size();
  }
  return success();
}

/// The gate undoing `kind`, for the parameterless kinds.
static std::optional<GateKind> getInverseKind(GateKind kind) {
  switch (kind) {
  case GateKind::X:
  case GateKind::Y:
  case GateKind::Z:
  case GateKind::H:
    return kind;
  case GateKind::S:
    return GateKind::Sdg;
  case GateKind::Sdg:
    return GateKind::S;
  case GateKind::T:
    return GateKind::Tdg;
  case GateKind::Tdg:
    return GateKind::T;
  case GateKind::P:
  case GateKind::RX:
  case GateKind::RY:
  case GateKind::RZ:
    return std::nullopt;
  }
  llvm_unreachable("unknown GateKind");
}

/// A gate directly following its inverse on the same controls and target
/// cancels: the results are the inputs of the first gate.
LogicalResult SingleOp::fold(FoldAdaptor /*adaptor*/, SmallVectorImpl<OpFoldResult>& results) {
  auto previous = getTarget().getDefiningOp<SingleOp>();
  if (!previous || getInverseKind(getKind()) != previous.getKind() || previous.getTargetOut() != getTarget() ||
      !llvm::equal(previous.getControlsOut(), getControls())) {
    return failure();
  }
  results.append(previous.getControls().begin(), previous.getControls().end());
  results.push_back(previous.getTarget());
  return success();
}

//===----------------------------------------------------------------------===//
// SinkOp
//===----------------------------------------------------------------------===//

LogicalResult SinkOp::verify() {
  auto measure = getQubit().getDefiningOp<MeasureOp>();
  if (!measure || measure.getQubitOut() != getQubit()) {
    return emitOpError("expected the qubit to come from a 'hlepgate.measure'; discarding an unmeasured qubit is not a "
                       "physical operation");
  }
  return success();
}

//===----------------------------------------------------------------------===//
// SplitOp / JoinOp
//===----------------------------------------------------------------------===//

LogicalResult SplitOp::inferReturnTypes(MLIRContext* context, std::optional<Location> location, Adaptor adaptor,
                                        SmallVectorImpl<Type>& inferredReturnTypes) {
  std::optional<unsigned> width = getRegisterWidth(adaptor.getReg().getType());
  if (!width) {
    return emitOptionalError(location, "expected a '!prelimhlep.lin<i<n>>' register");
  }
  inferredReturnTypes.assign(*width, getQubitType(context));
  return success();
}

/// Splitting a register that was just joined yields the joined qubits.
LogicalResult SplitOp::fold(FoldAdaptor /*adaptor*/, SmallVectorImpl<OpFoldResult>& results) {
  auto join = getReg().getDefiningOp<JoinOp>();
  if (!join) {
    return failure();
  }
  results.append(join.getQubits().begin(), join.getQubits().end());
  return success();
}

LogicalResult JoinOp::verify() {
  if (getRegisterWidth(getReg().getType()) != getQubits().size()) {
    return emitOpError("expected a register of ") << getQubits().size() << " qubits, got " << getReg().getType();
  }
  return success();
}

/// Joining all qubits of a register that was just split, in order, yields
/// the register.
OpFoldResult JoinOp::fold(FoldAdaptor /*adaptor*/) {
  auto split = getQubits().empty() ? nullptr : getQubits().front().getDefiningOp<SplitOp>();
  if (!split || !llvm::equal(split.getQubits(), getQubits())) {
    return {};
  }
  return split.getReg();
}
