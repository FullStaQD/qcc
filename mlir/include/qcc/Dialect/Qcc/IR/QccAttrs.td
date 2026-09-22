// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCC_IR_QCCATTRS_TD_
#define INCLUDE_QCC_DIALECT_QCC_IR_QCCATTRS_TD_

include "qcc/Dialect/Qcc/IR/QccDialect.td"
include "qcc/Dialect/Qcc/IR/QccInterfaces.td"

include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/OpBase.td" // the dialect doc generator needs `Op`, even for a dialect without ops.

//===----------------------------------------------------------------------===//
// MAGIC device attributes
//===----------------------------------------------------------------------===//

// An array parameter that is always printed and parsed with brackets, `[a, b, c]`. The default format drops the
// brackets in the last struct position, and cannot parse `dense<...> : tensor<...>` literals. See `Qcc.h`.
class QCC_ArrayRefParameter<string element, string desc> : ArrayRefParameter<element, desc> {
  let parser = "::qcc::detail::parseArray<" # element # ">($_parser)";
  let printer = "::qcc::detail::printArray($_printer, $_self)";
}

def QCC_MagicTrapAttr : QCC_Attr<"MagicTrap", "magic_trap"> {
  let summary = "One ion trap of a MAGIC device";
  let description = [{
        Describes one trap ("chain") of a MAGIC device: how many ions it can hold and how strongly the ions couple.

        `couplings` holds one matrix per possible occupancy: matrix `k` (0-based) is the `(k+1)x(k+1)` coupling matrix
        that applies when `k+1` ions are present in the trap, active or not. Entry `(i, j)` is the coupling strength
        between the ions at chain positions `i` and `j` (front = 0). The matrices are symmetric with a zero diagonal.

        Example (capacity 2):
        ```mlir
        #qcc.magic_trap<capacity = 2, couplings = [dense<0.0> : tensor<1x1xf64>,
                                                   dense<[[0.0, 297.4], [297.4, 0.0]]> : tensor<2x2xf64>]>
        ```
    }];

  let parameters = (ins
    "int64_t":$capacity,
    QCC_ArrayRefParameter<"::mlir::DenseElementsAttr", "coupling matrix per occupancy 1..capacity">:$couplings
  );

  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}

def QCC_MagicDeviceAttr : QCC_Attr<"MagicDevice", "magic_device", [QCC_DeviceAttrInterface]> {
  let summary = "A MAGIC device: ion traps with a permanent ZZ coupling";
  let description = [{
        The device description for the MAGIC architecture (trapped ions in one or more traps, coupled by a permanent
        ZZ interaction). It carries what the compiler needs and cannot derive from the program:

        - `name`: a human-readable name.
        - `time_unit_ns`: the base unit of a `magic.delay` in nanoseconds; delays are integer multiples of it.
        - `initial_occupancies`: the number of ions loaded into each trap at program start (index = trap id).
        - `traps`: one `#qcc.magic_trap` per trap.

        Passes and the exporter read it through the `MagicDevice` C++ class rather than through the attribute directly.

        Example:
        ```mlir
        #qcc.magic_device<name = "two-trap", time_unit_ns = 1000, initial_occupancies = [2, 1], traps = [#trap, #trap]>
        ```
    }];

  let parameters = (ins
    StringRefParameter<"human-readable device name">:$name,
    "int64_t":$time_unit_ns,
    ArrayRefParameter<"int64_t", "ions loaded at program start, per trap">:$initial_occupancies,
    QCC_ArrayRefParameter<"::qcc::MagicTrapAttr", "the traps, index = trap id">:$traps
  );

  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCATTRS_TD_
