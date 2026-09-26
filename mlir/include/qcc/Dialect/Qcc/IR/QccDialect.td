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
include "mlir/IR/OpBase.td" // the dialect doc generator needs `Op`, even for a dialect without ops.

//===----------------------------------------------------------------------===//
// Qcc dialect
//===----------------------------------------------------------------------===//

def Qcc_Dialect : Dialect {
    let summary = "Project-wide metadata: e.g. device description and the entry point marker.";
    let description = [{
        The `qcc` dialect owns the metadata that is meaningful across all quantum dialects of this project.

        - `qcc.entry_point` is a discardable unit attribute on a function (`func.func`, `llvm.func`) that marks *a*
          starting point of a quantum program.
        - `qcc.device` is a discardable attribute on the module that describes the device the program is compiled for.
          Its value can be any attribute implementing the `DeviceAttrInterface`. A concrete device description belongs
          to the dialect of its architecture, e.g. `#magic.device`.

        Example:
        ```mlir
        #trap = #magic.trap<capacity = 2, couplings = [dense<0.0> : tensor<1x1xf64>,
                                                       dense<[[0.0, 297.4], [297.4, 0.0]]> : tensor<2x2xf64>]>
        module attributes {qcc.device = #magic.device<name = "two-trap", time_unit_ns = 1000,
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
    let useDefaultAttributePrinterParser = 0; // set to 1 once we define attributes of our own.

    let discardableAttrs = (ins "::mlir::Attribute":$device,
                                "::mlir::UnitAttr":$entry_point);
    let hasOperationAttrVerify = 1;
}

//===----------------------------------------------------------------------===//
// Shared ODS helpers
//===----------------------------------------------------------------------===//

// An array parameter that is always printed and parsed with brackets, `[a, b, c]`. The default format only brackets a
// parameter that is not the last one in a `struct`, which would tie our syntax to the order of the parameters.
class QCC_ArrayRefParameter<string element, string desc> : ArrayRefParameter<element, desc> {
  let parser = "::qcc::detail::parseArray<" # element # ">($_parser)";
  let printer = "::qcc::detail::printArray($_printer, $_self)";
}

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCDIALECT_TD_
