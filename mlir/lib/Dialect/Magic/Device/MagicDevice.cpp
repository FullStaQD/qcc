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

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <memory>
#include <string>
#include <utility>

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
// MagicDevice: storage
//===----------------------------------------------------------------------===//

// One instance per device, shared by every copy of the `MagicDevice` handle, hence the derived `numIons`: it is
// computed once, with the rest of the data.
struct MagicDevice::Storage {
  struct Trap {
    IonCount capacity = 0;
    SmallVector<CouplingMatrix> couplings; // index n-1: the matrix for n ions present
  };

  std::string name;
  int64_t timeUnitNs = 0;
  SmallVector<IonCount> occupancies;
  SmallVector<Trap> traps;
  IonCount numIons = 0; // the sum of the occupancies
};

MagicDevice::MagicDevice(std::shared_ptr<const Storage> data) : storage(std::move(data)) {}

//===----------------------------------------------------------------------===//
// MagicDevice: construction
//===----------------------------------------------------------------------===//

MagicDevice MagicDevice::fromAttr(DeviceAttr attr) {
  Storage storage;
  storage.name = attr.getName().str();
  storage.timeUnitNs = attr.getTimeUnitNs();
  for (const int64_t occupancy : attr.getInitialOccupancies()) {
    storage.occupancies.push_back(static_cast<IonCount>(occupancy));
    storage.numIons += static_cast<IonCount>(occupancy);
  }
  for (TrapAttr trapAttr : attr.getTraps()) {
    Storage::Trap& trap = storage.traps.emplace_back();
    trap.capacity = static_cast<IonCount>(trapAttr.getCapacity());
    for (DenseElementsAttr matrix : trapAttr.getCouplings()) {
      trap.couplings.emplace_back(matrix);
    }
  }
  return MagicDevice(std::make_shared<const Storage>(std::move(storage)));
}

FailureOr<MagicDevice> MagicDevice::fromModule(ModuleOp module) {
  const StringRef attrName = QccDialect::DeviceAttrHelper::getNameStr();
  Attribute attr = QccDialect::DeviceAttrHelper(module.getContext()).getAttr(module);
  if (!attr) {
    return module.emitError() << "module carries no '" << attrName << "' attribute";
  }
  auto magicAttr = dyn_cast<DeviceAttr>(attr);
  if (!magicAttr) {
    return module.emitError() << "expected '" << attrName << "' to be a #magic.device, got " << attr;
  }
  return fromAttr(magicAttr);
}

FailureOr<MagicDevice> MagicDevice::fromFile(StringRef path, MLIRContext& ctx) {
  const FailureOr<Attribute> attr = parseDeviceFile(path, ctx);
  if (failed(attr)) {
    return failure();
  }
  auto magicAttr = dyn_cast<DeviceAttr>(*attr);
  if (!magicAttr) {
    return emitError(UnknownLoc::get(&ctx))
           << "expected device file '" << path << "' to describe a #magic.device, got " << *attr;
  }
  return fromAttr(magicAttr);
}

DeviceAttr MagicDevice::toAttr(MLIRContext& ctx) const {
  SmallVector<int64_t> occupancyList(storage->occupancies.begin(), storage->occupancies.end());
  SmallVector<TrapAttr> trapAttrs;
  for (const Storage::Trap& trap : storage->traps) {
    const SmallVector<DenseElementsAttr> couplings =
        llvm::map_to_vector(trap.couplings, [&](const CouplingMatrix& matrix) { return matrix.toAttr(ctx); });
    trapAttrs.push_back(TrapAttr::get(&ctx, trap.capacity, couplings));
  }
  return DeviceAttr::get(&ctx, storage->name, storage->timeUnitNs, occupancyList, trapAttrs);
}

//===----------------------------------------------------------------------===//
// MagicDevice: device data
//===----------------------------------------------------------------------===//

StringRef MagicDevice::name() const { return storage->name; }

unsigned MagicDevice::numTraps() const { return static_cast<unsigned>(storage->traps.size()); }

IonCount MagicDevice::capacity(TrapId trap) const {
  assert(trap < storage->traps.size() && "no such trap");
  return storage->traps[trap].capacity;
}

IonCount MagicDevice::initialOccupancy(TrapId trap) const {
  assert(trap < storage->occupancies.size() && "no such trap");
  return storage->occupancies[trap];
}

IonCount MagicDevice::numIons() const { return storage->numIons; }

int64_t MagicDevice::timeUnitNs() const { return storage->timeUnitNs; }

double MagicDevice::ticksToMicroseconds(Ticks ticks) const {
  return static_cast<double>(ticks) * static_cast<double>(storage->timeUnitNs) / 1000.0;
}

Ticks MagicDevice::microsecondsToTicks(double microseconds) const {
  return static_cast<Ticks>(std::llround(microseconds * 1000.0 / static_cast<double>(storage->timeUnitNs)));
}

const CouplingMatrix& MagicDevice::coupling(TrapId trap, IonCount n) const {
  assert(trap < storage->traps.size() && "no such trap");
  assert(n >= 1 && n <= storage->traps[trap].capacity && "occupancy out of range");
  return storage->traps[trap].couplings[n - 1];
}
