// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCC_TRANSFORMS_PASSES_TD_
#define INCLUDE_QCC_DIALECT_QCC_TRANSFORMS_PASSES_TD_

include "mlir/Pass/PassBase.td"

def QccAttachDevice : Pass<"qcc-attach-device", "mlir::ModuleOp"> {
  let summary = "Attaches the device description from a device file to the module.";

  let description = [{
      Reads a device file and copies its `qcc.device` attribute onto the module. A device file is a minimal module
      that carries only that attribute, so attribute aliases work:

      ```mlir
      #trap = #qcc.magic_trap<capacity = 2, couplings = [dense<0.0> : tensor<1x1xf64>,
                                                         dense<[[0.0, 1.0], [1.0, 0.0]]> : tensor<2x2xf64>]>
      module attributes {qcc.device = #qcc.magic_device<name = "two-trap", time_unit_ns = 1000,
                                                        initial_occupancies = [2, 1], traps = [#trap, #trap]>} {}
      ```

      Fails if the file cannot be read, carries no `qcc.device` attribute, or if the module already has one.
  }];

  let options = [
    Option<"file", "file", "std::string", /*default=*/"\"\"", "Path of the device file.">
  ];

  let dependentDialects = ["qcc::QccDialect"];
}

#endif // INCLUDE_QCC_DIALECT_QCC_TRANSFORMS_PASSES_TD_
