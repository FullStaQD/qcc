// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Aux_/IR/Aux_.h"
#include "qcc/Dialect/Magic/IR/Magic.h"

#include "mlir/IR/Attributes.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/DialectImplementation.h" // IWYU pragma: keep
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h"

#include "llvm/ADT/TypeSwitch.h"      // IWYU pragma: keep
#include "llvm/Support/raw_ostream.h" // IWYU pragma: keep

using namespace mlir;
using namespace qcc::magic;

#include "qcc/Dialect/Magic/IR/MagicDialect.cpp.inc"

namespace {

/// Prints the dialect's types and attributes as aliases, which keeps the IR readable: e.g. every `!magic.ion_chain`
/// becomes `!chain`, `!chain1`, ..., so the ops read like `magic.delay %c {ticks = 10} : !chain2`.
struct MagicOpAsmDialectInterface final : OpAsmDialectInterface {
  using OpAsmDialectInterface::OpAsmDialectInterface;

  AliasResult getAlias(Type type, raw_ostream& os) const override {
    if (isa<IonChainType>(type)) {
      os << "chain";
      return AliasResult::OverridableAlias;
    }
    return AliasResult::NoAlias;
  }

  AliasResult getAlias(Attribute attr, raw_ostream& os) const override {
    if (isa<TrapAttr>(attr)) {
      os << "magic_trap";
      return AliasResult::OverridableAlias;
    }
    if (isa<DeviceAttr>(attr)) {
      os << "magic_device";
      return AliasResult::OverridableAlias;
    }
    return AliasResult::NoAlias;
  }
};

} // namespace

void MagicDialect::initialize() {
  registerAttributes();
  registerTypes();

  addOperations<
#define GET_OP_LIST
#include "qcc/Dialect/Magic/IR/MagicOps.cpp.inc"
      >();

  addInterfaces<MagicOpAsmDialectInterface>();
}

LogicalResult MagicDialect::verifyOperationAttribute(Operation* op, NamedAttribute attr) {
  const StringRef name = attr.getName().getValue();

  if (name == GarbageResultAttrHelper::getNameStr()) {
    if (!isa<qcc::aux::RecordIntOp>(op)) {
      return op->emitOpError() << "attribute '" << name << "' is only valid on 'aux.record_int'";
    }
    if (!isa<UnitAttr>(attr.getValue())) {
      return op->emitOpError() << "attribute '" << name << "' must be a unit attribute, got " << attr.getValue();
    }
    return success();
  }

  return success();
}
