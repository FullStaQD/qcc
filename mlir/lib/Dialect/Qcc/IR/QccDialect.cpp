// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectImplementation.h" // IWYU pragma: keep
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "mlir/Parser/Parser.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h" // IWYU pragma: keep
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/raw_ostream.h"

#include <cstdint>
#include <memory>
#include <system_error>

using namespace mlir;
using namespace qcc;

#include "qcc/Dialect/Qcc/IR/QccDialect.cpp.inc"
#include "qcc/Dialect/Qcc/IR/QccInterfaces.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/Qcc/IR/QccAttrs.cpp.inc"

//===----------------------------------------------------------------------===//
// Dialect
//===----------------------------------------------------------------------===//

namespace {

/// Prints the device attributes as aliases (`#magic_trap`, `#magic_device`), which keeps modules readable: identical
/// traps are printed once, and the module header stays a single line.
struct QccOpAsmDialectInterface final : OpAsmDialectInterface {
  using OpAsmDialectInterface::OpAsmDialectInterface;

  AliasResult getAlias(Attribute attr, raw_ostream& os) const override {
    if (isa<MagicTrapAttr>(attr)) {
      os << "magic_trap";
      return AliasResult::OverridableAlias;
    }
    if (isa<MagicDeviceAttr>(attr)) {
      os << "magic_device";
      return AliasResult::OverridableAlias;
    }
    return AliasResult::NoAlias;
  }
};

} // namespace

void QccDialect::initialize() {
  addAttributes<
#define GET_ATTRDEF_LIST
#include "qcc/Dialect/Qcc/IR/QccAttrs.cpp.inc"
      >();

  addInterfaces<QccOpAsmDialectInterface>();
}

LogicalResult QccDialect::verifyOperationAttribute(Operation* op, NamedAttribute attr) {
  const StringRef name = attr.getName().getValue();

  if (name == DeviceAttrHelper::getNameStr()) {
    if (!isa<ModuleOp>(op)) {
      return op->emitOpError() << "attribute '" << name << "' is only valid on a module";
    }
    if (!isa<DeviceAttrInterface>(attr.getValue())) {
      return op->emitOpError() << "attribute '" << name << "' must be a device description, got " << attr.getValue();
    }
    return success();
  }

  if (name == EntryPointAttrHelper::getNameStr()) {
    if (!isa<FunctionOpInterface>(op)) {
      return op->emitOpError() << "attribute '" << name << "' is only valid on a function";
    }
    if (!isa<UnitAttr>(attr.getValue())) {
      return op->emitOpError() << "attribute '" << name << "' must be a unit attribute, got " << attr.getValue();
    }
    return success();
  }

  return success();
}

//===----------------------------------------------------------------------===//
// MagicTrapAttr
//===----------------------------------------------------------------------===//

LogicalResult MagicTrapAttr::verify(function_ref<InFlightDiagnostic()> emitError, int64_t capacity,
                                    ArrayRef<DenseElementsAttr> couplings) {
  if (capacity < 1) {
    return emitError() << "capacity must be at least 1, got " << capacity;
  }
  if (std::cmp_not_equal(couplings.size(), capacity)) {
    return emitError() << "expected one coupling matrix per occupancy 1.." << capacity << ", got " << couplings.size();
  }

  for (auto [index, matrix] : llvm::enumerate(couplings)) {
    const int64_t numIons = static_cast<int64_t>(index) + 1;
    if (!matrix) {
      return emitError() << "coupling matrix for " << numIons << " ions is missing";
    }

    const ShapedType type = matrix.getType();
    if (!type.getElementType().isF64() || type.getRank() != 2 || type.getDimSize(0) != numIons ||
        type.getDimSize(1) != numIons) {
      return emitError() << "coupling matrix for " << numIons << " ions must have type tensor<" << numIons << "x"
                         << numIons << "xf64>, got " << type;
    }

    const SmallVector<double> values(matrix.getValues<double>());
    for (int64_t i = 0; i < numIons; ++i) {
      if (values[(i * numIons) + i] != 0.0) {
        return emitError() << "coupling matrix for " << numIons << " ions must have a zero diagonal";
      }
      for (int64_t j = i + 1; j < numIons; ++j) {
        if (values[(i * numIons) + j] != values[(j * numIons) + i]) {
          return emitError() << "coupling matrix for " << numIons << " ions must be symmetric";
        }
      }
    }
  }

  return success();
}

//===----------------------------------------------------------------------===//
// MagicDeviceAttr
//===----------------------------------------------------------------------===//

LogicalResult MagicDeviceAttr::verify(function_ref<InFlightDiagnostic()> emitError, StringRef name, int64_t timeUnitNs,
                                      ArrayRef<int64_t> initialOccupancies, ArrayRef<MagicTrapAttr> traps) {
  if (name.empty()) {
    return emitError() << "name must not be empty";
  }
  if (timeUnitNs <= 0) {
    return emitError() << "time_unit_ns must be positive, got " << timeUnitNs;
  }
  if (traps.empty()) {
    return emitError() << "expected at least one trap";
  }
  if (initialOccupancies.size() != traps.size()) {
    return emitError() << "expected one initial occupancy per trap, got " << initialOccupancies.size()
                       << " occupancies for " << traps.size() << " traps";
  }

  for (auto [trap, occupancy] : llvm::enumerate(initialOccupancies)) {
    if (!traps[trap]) {
      return emitError() << "trap " << trap << " is missing";
    }
    const int64_t capacity = traps[trap].getCapacity();
    if (occupancy < 0 || occupancy > capacity) {
      return emitError() << "initial occupancy of trap " << trap << " must be in 0.." << capacity << ", got "
                         << occupancy;
    }
  }

  return success();
}

//===----------------------------------------------------------------------===//
// Device files
//===----------------------------------------------------------------------===//

FailureOr<Attribute> qcc::parseDeviceFile(StringRef path, MLIRContext& ctx) {
  // Read the file ourselves so that a missing file is reported at a location the caller can match.
  auto buffer = llvm::MemoryBuffer::getFile(path);
  if (const std::error_code error = buffer.getError()) {
    return emitError(UnknownLoc::get(&ctx)) << "cannot read device file '" << path << "': " << error.message();
  }

  llvm::SourceMgr sourceMgr;
  sourceMgr.AddNewSourceBuffer(std::move(*buffer), llvm::SMLoc());

  // Parsing (with verification) already checks the attribute itself; see `QccDialect::verifyOperationAttribute`.
  const OwningOpRef<ModuleOp> module = parseSourceFile<ModuleOp>(sourceMgr, ParserConfig(&ctx));
  if (!module) {
    return failure();
  }

  Attribute device = QccDialect::DeviceAttrHelper(&ctx).getAttr(module.get());
  if (!device) {
    return module.get().emitError() << "device file '" << path << "' carries no '"
                                    << QccDialect::DeviceAttrHelper::getNameStr() << "' attribute";
  }
  return device;
}
