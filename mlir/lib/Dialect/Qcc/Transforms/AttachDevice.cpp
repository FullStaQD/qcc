// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/IR/Magic.h" // IWYU pragma: keep, a device file may carry a `#magic.device`.
#include "qcc/Dialect/Qcc/IR/Qcc.h"
#include "qcc/Dialect/Qcc/Transforms/Passes.h" // IWYU pragma: keep

#include "mlir/IR/Attributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep

using namespace mlir;

namespace qcc {

#define GEN_PASS_DEF_QCCATTACHDEVICE
#include "qcc/Dialect/Qcc/Transforms/Passes.h.inc"

namespace {

struct QccAttachDevice final : impl::QccAttachDeviceBase<QccAttachDevice> {
  using QccAttachDeviceBase::QccAttachDeviceBase;

protected:
  void runOnOperation() override {
    ModuleOp module = getOperation();
    QccDialect::DeviceAttrHelper deviceAttr(module.getContext());

    if (file.empty()) {
      module.emitError() << "option 'file' is required: the path of the device file";
      return signalPassFailure();
    }
    if (deviceAttr.isAttrPresent(module)) {
      module.emitError() << "module already carries a '" << QccDialect::DeviceAttrHelper::getNameStr() << "' attribute";
      return signalPassFailure();
    }

    const FailureOr<Attribute> device = parseDeviceFile(file, *module.getContext());
    if (failed(device)) {
      return signalPassFailure();
    }
    deviceAttr.setAttr(module, *device);
  }
};

} // namespace
} // namespace qcc
