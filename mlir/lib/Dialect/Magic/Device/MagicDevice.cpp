// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/Device/MagicDevice.h"

#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/IR/Attributes.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/MLIRContext.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cassert>
#include <cmath>
#include <cstdint>

using namespace mlir;
using namespace qcc;
using namespace qcc::magic;

//===----------------------------------------------------------------------===//
// CouplingMatrix
//===----------------------------------------------------------------------===//

CouplingMatrix::CouplingMatrix(DenseElementsAttr matrix) : data(matrix.getValues<double>()) {
  const ShapedType type = matrix.getType();
  assert(type.getRank() == 2 && type.getDimSize(0) == type.getDimSize(1) && "expected a square matrix");
  numIons = static_cast<IonCount>(type.getDimSize(0));
}

double CouplingMatrix::operator()(unsigned i, unsigned j) const {
  assert(i < numIons && j < numIons && "position out of range");
  return data[(i * numIons) + j];
}

DenseElementsAttr CouplingMatrix::toAttr(MLIRContext& ctx) const {
  auto type = RankedTensorType::get({numIons, numIons}, Float64Type::get(&ctx));
  return DenseElementsAttr::get(type, ArrayRef(data));
}

//===----------------------------------------------------------------------===//
// MagicDevice: construction
//===----------------------------------------------------------------------===//

MagicDevice MagicDevice::fromAttr(MagicDeviceAttr attr) {
  MagicDevice device;
  device.deviceName = attr.getName().str();
  device.timeUnit = attr.getTimeUnitNs();
  for (const int64_t occupancy : attr.getInitialOccupancies()) {
    device.occupancies.push_back(static_cast<IonCount>(occupancy));
  }
  for (MagicTrapAttr trapAttr : attr.getTraps()) {
    Trap& trap = device.traps.emplace_back();
    trap.capacity = static_cast<IonCount>(trapAttr.getCapacity());
    for (DenseElementsAttr matrix : trapAttr.getCouplings()) {
      trap.couplings.emplace_back(matrix);
    }
  }
  return device;
}

FailureOr<MagicDevice> MagicDevice::fromModule(ModuleOp module) {
  const StringRef attrName = QccDialect::DeviceAttrHelper::getNameStr();
  Attribute attr = QccDialect::DeviceAttrHelper(module.getContext()).getAttr(module);
  if (!attr) {
    return module.emitError() << "module carries no '" << attrName << "' attribute";
  }
  auto magicAttr = dyn_cast<MagicDeviceAttr>(attr);
  if (!magicAttr) {
    return module.emitError() << "expected '" << attrName << "' to be a #qcc.magic_device, got " << attr;
  }
  return fromAttr(magicAttr);
}

FailureOr<MagicDevice> MagicDevice::fromFile(StringRef path, MLIRContext& ctx) {
  const FailureOr<Attribute> attr = parseDeviceFile(path, ctx);
  if (failed(attr)) {
    return failure();
  }
  auto magicAttr = dyn_cast<MagicDeviceAttr>(*attr);
  if (!magicAttr) {
    return emitError(UnknownLoc::get(&ctx))
           << "expected device file '" << path << "' to describe a #qcc.magic_device, got " << *attr;
  }
  return fromAttr(magicAttr);
}

MagicDeviceAttr MagicDevice::toAttr(MLIRContext& ctx) const {
  SmallVector<int64_t> occupancyList(occupancies.begin(), occupancies.end());
  SmallVector<MagicTrapAttr> trapAttrs;
  for (const Trap& trap : traps) {
    const SmallVector<DenseElementsAttr> couplings =
        llvm::map_to_vector(trap.couplings, [&](const CouplingMatrix& matrix) { return matrix.toAttr(ctx); });
    trapAttrs.push_back(MagicTrapAttr::get(&ctx, trap.capacity, couplings));
  }
  return MagicDeviceAttr::get(&ctx, deviceName, timeUnit, occupancyList, trapAttrs);
}

//===----------------------------------------------------------------------===//
// MagicDevice: device data
//===----------------------------------------------------------------------===//

IonCount MagicDevice::capacity(TrapId trap) const {
  assert(trap < traps.size() && "no such trap");
  return traps[trap].capacity;
}

IonCount MagicDevice::initialOccupancy(TrapId trap) const {
  assert(trap < occupancies.size() && "no such trap");
  return occupancies[trap];
}

IonCount MagicDevice::numIons() const {
  IonCount total = 0;
  for (const IonCount occupancy : occupancies) {
    total += occupancy;
  }
  return total;
}

double MagicDevice::ticksToMicroseconds(Ticks ticks) const {
  return static_cast<double>(ticks) * static_cast<double>(timeUnit) / 1000.0;
}

Ticks MagicDevice::microsecondsToTicks(double microseconds) const {
  return static_cast<Ticks>(std::llround(microseconds * 1000.0 / static_cast<double>(timeUnit)));
}

const CouplingMatrix& MagicDevice::coupling(TrapId trap, IonCount n) const {
  assert(trap < traps.size() && "no such trap");
  assert(n >= 1 && n <= traps[trap].capacity && "occupancy out of range");
  return traps[trap].couplings[n - 1];
}
