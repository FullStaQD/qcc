// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCC_IR_QCCDIALECT_TD_
#define INCLUDE_QCC_DIALECT_QCC_IR_QCCDIALECT_TD_

include "mlir/IR/DialectBase.td"
include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// Qcc dialect
//===----------------------------------------------------------------------===//

def QccDialect : Dialect {
    let summary = "Project-wide metadata: the device description and the entry point marker.";
    let description = [{
        The `qcc` dialect owns the metadata that is meaningful across all quantum dialects of this project. It defines
        no operations and no types, only attributes:

        - `qcc.entry_point` is a discardable unit attribute on a function (`func.func`, `llvm.func`) that marks *a*
          starting point of a quantum program.
        - `qcc.device` is a discardable attribute on the module that describes the device the program is compiled for.
          Its value can be any attribute implementing the `DeviceAttrInterface`; `#qcc.magic_device` is the first one.

        Example:
        ```mlir
        #trap = #qcc.magic_trap<capacity = 2, couplings = [dense<0.0> : tensor<1x1xf64>,
                                                           dense<[[0.0, 297.4], [297.4, 0.0]]> : tensor<2x2xf64>]>
        module attributes {qcc.device = #qcc.magic_device<name = "two-trap", time_unit_ns = 1000,
                                                          initial_occupancies = [2, 1], traps = [#trap, #trap]>} {
          func.func @main() attributes {qcc.entry_point} {
            return
          }
        }
        ```
    }];

    let name = "qcc";
    let cppNamespace = "::qcc";

    let useDefaultTypePrinterParser = 0;      // set to 1 once we define types of our own.
    let useDefaultAttributePrinterParser = 1;

    let discardableAttrs = (ins "::mlir::Attribute":$device,
                                "::mlir::UnitAttr":$entry_point);
    let hasOperationAttrVerify = 1;
}

class QCC_Attr<string name, string attrMnemonic, list<Trait> traits = []> : AttrDef<QccDialect, name, traits> {
  let mnemonic = attrMnemonic;
}

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCDIALECT_TD_
