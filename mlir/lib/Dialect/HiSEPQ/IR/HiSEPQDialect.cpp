// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/HiSEPQ/IR/HiSEPQ.h"

#include "mlir/Dialect/QC/IR/QCDialect.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectImplementation.h" // IWYU pragma: keep
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Support/LogicalResult.h"

#include "llvm/ADT/TypeSwitch.h" // IWYU pragma: keep

using namespace mlir;
using namespace qcc::hisepq;

#include "qcc/Dialect/HiSEPQ/IR/HiSEPQDialect.cpp.inc"
#include "qcc/Dialect/HiSEPQ/IR/HiSEPQEnums.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/HiSEPQ/IR/HiSEPQAttrs.cpp.inc"

#define GET_OP_CLASSES
#include "qcc/Dialect/HiSEPQ/IR/HiSEPQOps.cpp.inc"

void HiSEPQDialect::initialize() {
  addTypes<>();

  addAttributes<
#define GET_ATTRDEF_LIST
#include "qcc/Dialect/HiSEPQ/IR/HiSEPQAttrs.cpp.inc"
      >();

  addOperations<
#define GET_OP_LIST
#include "qcc/Dialect/HiSEPQ/IR/HiSEPQOps.cpp.inc"
      >();
}

//===----------------------------------------------------------------------===//
// Verifiers
//===----------------------------------------------------------------------===//

/// Checks that an optional mask has one lane per qubit lane.
///
/// This cannot be expressed with `AllShapesMatch`: that trait dereferences the operand
/// unconditionally, so it would crash on the (legal) absent mask rather than accept it.
static LogicalResult verifyMaskLaneCount(Operation* op, Value qubits, Value mask) {
  if (!mask) {
    return success();
  }

  auto numQubitLanes = cast<VectorType>(qubits.getType()).getNumElements();
  auto numMaskLanes = cast<VectorType>(mask.getType()).getNumElements();

  if (numQubitLanes != numMaskLanes) {
    return op->emitOpError("expects the mask to have one lane per qubit, but got ")
           << numMaskLanes << " mask lane(s) for " << numQubitLanes << " qubit lane(s)";
  }

  return success();
}

LogicalResult SingleOp::verify() { return verifyMaskLaneCount(*this, getQubits(), getMask()); }

LogicalResult PairOp::verify() { return verifyMaskLaneCount(*this, getCtrls(), getMask()); }

LogicalResult MzOp::verify() { return verifyMaskLaneCount(*this, getQubits(), getMask()); }

// FIXME: verifier for pair: same num ctrls and tgts.

//===----------------------------------------------------------------------===//
// External models
//===----------------------------------------------------------------------===//

namespace {

// FIXME: learn more about the constraints on the element type. Notably the size
// constraint. That we have !qc.qubit having size of 8 bits is something we have
// to determine at compile time. This is not an intrinsic property of !qc.qubit.

/// Opts `!qc.qubit` into being a vector element type.
///
/// `VectorElementTypeInterface` has no methods; it is purely a marker that a type may appear as a
/// `VectorType` element. We attach it from here rather than on the type itself because
/// `mlir::qc::QubitType` belongs to mqt-core, which we consume as a pinned dependency.
///
/// Upstream currently discourages attaching this interface to downstream types, on the grounds that
/// the properties required of a vector element (notably a compile-time size) are not yet pinned
/// down. A qubit reference does have such a size here -- the hardware carries qubit indices as i8
/// lanes -- and we only ever build these vectors ourselves. Drop this model if mqt-core marks the
/// type itself, the way it already did for `MemRefElementTypeInterface`.
struct QubitVectorElement : public VectorElementTypeInterface::ExternalModel<QubitVectorElement, qc::QubitType> {};

} // namespace

void qcc::hisepq::registerQubitVectorElementTypeInterfaceExternalModel(DialectRegistry& registry) {
  // Keyed on the QC dialect so the attachment happens when that dialect is loaded, which is before
  // any `vector<Nx!qc.qubit>` can be parsed.
  registry.addExtension(
      +[](MLIRContext* ctx, qc::QCDialect* /*dialect*/) { qc::QubitType::attachInterface<QubitVectorElement>(*ctx); });
}
