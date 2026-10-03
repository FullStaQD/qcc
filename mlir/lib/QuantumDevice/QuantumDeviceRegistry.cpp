// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/QuantumDevice/QuantumDeviceRegistry.h"

#include "qcc/Dialect/Magic/Export/Export.h"
#include "qcc/QuantumDevice/Magic/MagicPipeline.h"

#include <vector>

namespace qcc {

llvm::ArrayRef<QuantumDeviceKind> getQuantumDeviceKinds() {
  static const std::vector<QuantumDeviceKind> devices = {
      {
          .name = noQuantumDeviceName,
          .description = "No quantum device: no device-specific lowering",
          .addLoweringPasses = [](mlir::PassManager& /*pm*/) {},
      },
      {
          .name = "magic",
          .description = "MAGIC architecture: ion traps with a permanent ZZ coupling",
          .addLoweringPasses = [](mlir::PassManager& pm) { addLoweringPassesMagic(pm); },
          .emitProgram = [](mlir::ModuleOp module, llvm::raw_ostream& os) { return magic::exportProgram(module, os); },
      },
  };

  return devices;
}

const QuantumDeviceKind* lookupQuantumDeviceKind(llvm::StringRef name) {
  for (const QuantumDeviceKind& device : getQuantumDeviceKinds()) {
    if (device.name == name) {
      return &device;
    }
  }
  return nullptr;
}

} // namespace qcc
