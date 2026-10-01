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
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "mlir/Parser/Parser.h"

#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/SourceMgr.h"

#include <memory>
#include <system_error>

using namespace mlir;
using namespace qcc;

#include "qcc/Dialect/Qcc/IR/QccDialect.cpp.inc"
#include "qcc/Dialect/Qcc/IR/QccInterfaces.cpp.inc"

//===----------------------------------------------------------------------===//
// Dialect
//===----------------------------------------------------------------------===//

// The dialect defines no attributes and no types of its own: it only names the module and function attributes
// declared in `QccDialect.td`, which need no registration.
void QccDialect::initialize() {}

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
