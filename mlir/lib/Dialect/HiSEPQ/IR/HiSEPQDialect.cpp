// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/HiSEPQ/HiSEPQHardware.h"
#include "qcc/Dialect/HiSEPQ/IR/HiSEPQ.h"

#include "mlir/Dialect/DLTI/DLTI.h"
#include "mlir/Dialect/QC/IR/QCDialect.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectImplementation.h" // IWYU pragma: keep
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"
#include "mlir/Support/LogicalResult.h"

#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/TypeSwitch.h" // IWYU pragma: keep
#include "llvm/Support/MathExtras.h"

#include <cstdint>

using namespace mlir;
using namespace qcc::hisepq;

#include "qcc/Dialect/HiSEPQ/IR/HiSEPQDialect.cpp.inc"
#include "qcc/Dialect/HiSEPQ/IR/HiSEPQEnums.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/HiSEPQ/IR/HiSEPQAttrs.cpp.inc"

#define GET_OP_CLASSES
#include "qcc/Dialect/HiSEPQ/IR/HiSEPQOps.cpp.inc"

//===----------------------------------------------------------------------===//
// Target description
//===----------------------------------------------------------------------===//

/// Validates the `hisepq.target` module attribute.
///
/// MLIR routes a discardable attribute to the dialect its name prefix identifies, which is what
/// lets a typo -- in the key or in the value -- surface as a diagnostic on the module rather than
/// as a surprise inside a lowering. It is also why the attribute carries the `hisepq` prefix.
LogicalResult HiSEPQDialect::verifyOperationAttribute(Operation* op, NamedAttribute attribute) {
  const StringRef name = attribute.getName().getValue();
  if (name != targetAttrName) {
    return op->emitError() << "unknown '" << getDialectNamespace() << "' attribute '" << name << "'";
  }

  auto target = dyn_cast<MapAttr>(attribute.getValue());
  if (!target) {
    return op->emitError() << "'" << name << "' expects a '#dlti.map'";
  }

  for (DataLayoutEntryInterface entry : target.getEntries()) {
    auto key = dyn_cast<StringAttr>(entry.getKey());
    if (!key || key.getValue() != minVLenKey) {
      return op->emitError() << "'" << name << "' has an unknown entry, expected '" << minVLenKey << "'";
    }

    auto value = dyn_cast<IntegerAttr>(entry.getValue());
    if (!value) {
      return op->emitError() << "'" << minVLenKey << "' expects an integer attribute";
    }

    // Anything below `rvvBitsPerBlock` would make `vscale` a fraction, and anything that is not a
    // power of two is not a VLEN at all.
    const uint64_t minVLen = value.getValue().getLimitedValue();
    if (minVLen < rvvBitsPerBlock || !llvm::isPowerOf2_64(minVLen)) {
      return op->emitError() << "'" << minVLenKey << "' expects a power of two of at least " << rvvBitsPerBlock
                             << ", got " << value;
    }
  }

  return success();
}

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
/// elements -- and we only ever build these vectors ourselves. Drop this model if mqt-core marks the
/// type itself, the way it already did for `MemRefElementTypeInterface`.
struct QubitVectorElement : public VectorElementTypeInterface::ExternalModel<QubitVectorElement, qc::QubitType> {};

} // namespace

void qcc::hisepq::registerQubitVectorElementTypeInterfaceExternalModel(DialectRegistry& registry) {
  // Keyed on the QC dialect so the attachment happens when that dialect is loaded, which is before
  // any `vector<Nx!qc.qubit>` can be parsed.
  registry.addExtension(
      +[](MLIRContext* ctx, qc::QCDialect* /*dialect*/) { qc::QubitType::attachInterface<QubitVectorElement>(*ctx); });
}
