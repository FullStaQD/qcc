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
include "mlir/IR/OpBase.td"

//===----------------------------------------------------------------------===//
// Qcc dialect
//===----------------------------------------------------------------------===//

def Qcc_Dialect : Dialect {
    let summary = "Shared metadata, types, etc throughout all of our dialects.";
    let description = [{
        The `qcc` dialect is to this project what the builtin dialect is to MLIR: it owns what is meaningful across all
        of its quantum dialects.

        `!qcc.qubit` is the qubit type for a value-semantics context. It follows an affine type discipline: A qubit
        value may be consumed at most once on any execution path (no-cloning). It may also be left unused, which traces
        the qubit out. *A* way to enforce this is the `SingleUseQubits` trait which is designed for use with IR centered
        around the `qcirc` dialect.

        The following IR snippet shows a module with an attached MAGIC (Ions) device and a function marked as the entry
        point.

        ```mlir
        #trap = #magic.trap<capacity = 2, couplings = [dense<0.0> : tensor<1x1xf64>,
                                                       dense<[[0.0, 297.4], [297.4, 0.0]]> : tensor<2x2xf64>]>
        module attributes {qcc.device = #magic.device<name = "two-trap", time_unit_ns = 1000, traps = [#trap, #trap]>} {
          func.func @main() attributes {qcc.entry_point} {
            %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
            return
          }
        }
        ```
    }];

    let name = "qcc";
    let cppNamespace = "::qcc";

    let useDefaultTypePrinterParser = 1;
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
