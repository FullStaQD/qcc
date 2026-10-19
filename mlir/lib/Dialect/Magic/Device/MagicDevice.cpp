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
#include "mlir/IR/Operation.h"
#include "mlir/IR/Types.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <iterator>
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
  numIons = type.getDimSize(0);
}

double CouplingMatrix::operator()(int64_t i, int64_t j) const {
  assert(i >= 0 && i < numIons && j >= 0 && j < numIons && "position out of range");
  return data[(i * numIons) + j];
}

DenseElementsAttr CouplingMatrix::toAttr(MLIRContext& ctx) const {
  auto type = RankedTensorType::get({numIons, numIons}, Float64Type::get(&ctx));
  return DenseElementsAttr::get(type, ArrayRef(data));
}

//===----------------------------------------------------------------------===//
// MagicDevice: storage
//===----------------------------------------------------------------------===//

// One instance per device, shared by every copy of the `MagicDevice` handle.
struct MagicDevice::Storage {
  struct Trap {
    IonCount capacity = 0;
    SmallVector<CouplingMatrix> couplings; // index n-1: the matrix for n ions present
  };

  std::string name;
  int64_t timeUnitNs = 0;
  SmallVector<Trap> traps;
};

MagicDevice::MagicDevice(std::shared_ptr<const Storage> data) : storage(std::move(data)) {}

//===----------------------------------------------------------------------===//
// MagicDevice: construction
//===----------------------------------------------------------------------===//

MagicDevice MagicDevice::fromAttr(DeviceAttr attr) {
  Storage storage;
  storage.name = attr.getName().str();
  storage.timeUnitNs = attr.getTimeUnitNs();
  for (TrapAttr trapAttr : attr.getTraps()) {
    Storage::Trap& trap = storage.traps.emplace_back();
    trap.capacity = trapAttr.getCapacity();
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

FailureOr<MagicDevice> MagicDevice::fromParentModule(Operation* op) {
  auto module = op->getParentOfType<ModuleOp>();
  if (!module) {
    return op->emitError() << "is not inside a module, which would carry the device";
  }
  return fromModule(module);
}

FailureOr<MagicDevice> MagicDevice::fromParentModuleChecked(Operation* op) {
  FailureOr<MagicDevice> device = fromParentModule(op);
  if (failed(device)) {
    return failure();
  }

  bool fits = true;
  op->walk([&](Operation* nested) {
    for (const Type type : nested->getResultTypes()) {
      auto chain = dyn_cast<IonChainType>(type);
      if (!chain || llvm::is_contained(nested->getOperandTypes(), type)) {
        continue;
      }
      if (chain.getTrap() >= device->numTraps()) {
        nested->emitOpError() << "produces a chain of trap " << chain.getTrap() << ", but the device has "
                              << device->numTraps() << " traps";
        fits = false;
        continue;
      }
      const IonCount capacity = device->capacity(chain.getTrap());
      if (chain.getNumIons() > capacity) {
        nested->emitOpError() << "puts " << chain.getNumIons() << " ions into trap " << chain.getTrap()
                              << ", which holds at most " << capacity;
        fits = false;
      }
    }
  });

  if (!fits) {
    return failure();
  }

  return device;
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
  SmallVector<TrapAttr> trapAttrs;
  for (const Storage::Trap& trap : storage->traps) {
    const SmallVector<DenseElementsAttr> couplings =
        llvm::map_to_vector(trap.couplings, [&](const CouplingMatrix& matrix) { return matrix.toAttr(ctx); });
    trapAttrs.push_back(TrapAttr::get(&ctx, trap.capacity, couplings));
  }
  return DeviceAttr::get(&ctx, storage->name, storage->timeUnitNs, trapAttrs);
}

//===----------------------------------------------------------------------===//
// MagicDevice: device data
//===----------------------------------------------------------------------===//

StringRef MagicDevice::name() const { return storage->name; }

int64_t MagicDevice::numTraps() const { return std::ssize(storage->traps); }

IonCount MagicDevice::capacity(TrapId trap) const {
  assert(trap >= 0 && trap < numTraps() && "no such trap");
  return storage->traps[trap].capacity;
}

int64_t MagicDevice::timeUnitNs() const { return storage->timeUnitNs; }

double MagicDevice::ticksToMicroseconds(Ticks ticks) const {
  return static_cast<double>(ticks) * static_cast<double>(storage->timeUnitNs) / 1000.0;
}

Ticks MagicDevice::microsecondsToTicks(double microseconds) const {
  return static_cast<Ticks>(std::llround(microseconds * 1000.0 / static_cast<double>(storage->timeUnitNs)));
}

const CouplingMatrix& MagicDevice::coupling(TrapId trap, IonCount n) const {
  assert(trap >= 0 && trap < numTraps() && "no such trap");
  assert(n >= 1 && n <= storage->traps[trap].capacity && "occupancy out of range");
  return storage->traps[trap].couplings[n - 1];
}
