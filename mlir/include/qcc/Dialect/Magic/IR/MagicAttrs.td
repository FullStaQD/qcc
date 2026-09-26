// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_MAGIC_IR_MAGICATTRS_TD_
#define INCLUDE_QCC_DIALECT_MAGIC_IR_MAGICATTRS_TD_

include "qcc/Dialect/Magic/IR/MagicDialect.td"
include "qcc/Dialect/Qcc/IR/QccDialect.td"
include "qcc/Dialect/Qcc/IR/QccInterfaces.td"

include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// MAGIC device attributes
//===----------------------------------------------------------------------===//

class Magic_Attr<string name, string attrMnemonic, list<Trait> traits = []> : AttrDef<Magic_Dialect, name, traits> {
  let mnemonic = attrMnemonic;
}

def Magic_TrapAttr : Magic_Attr<"Trap", "trap"> {
  let summary = "One ion trap of a MAGIC device";
  let description = [{
        Describes one trap ("chain") of a MAGIC device: how many ions it can hold and how strongly the ions couple.

        `couplings` holds one matrix per possible occupancy: matrix `k` (0-based) is the `(k+1)x(k+1)` coupling matrix
        that applies when `k+1` ions are present in the trap, active or not. Entry `(i, j)` is the coupling strength
        between the ions at chain positions `i` and `j` (front = 0). The matrices are symmetric with a zero diagonal.

        Example:
        ```mlir
        #magic.trap<capacity = 2, couplings = [dense<0.0> : tensor<1x1xf64>,
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

def Magic_DeviceAttr : Magic_Attr<"Device", "device", [QCC_DeviceAttrInterface]> {
  let summary = "A MAGIC device: ion traps with a permanent ZZ coupling";
  let description = [{
        The device description for the MAGIC architecture (trapped ions in one or more traps, coupled by a permanent ZZ
        interaction). It is a possible value of the module attribute `qcc.device` and carries what the compiler needs
        and cannot derive from the program:

        - `name`: a human-readable name.
        - `time_unit_ns`: the base unit of a `magic.delay` in nanoseconds; delays are integer multiples of it.
        - `initial_occupancies`: the number of ions loaded into each trap at program start (index = trap id).
        - `traps`: one `#magic.trap` per trap.

        Passes and the exporter read it through the `MagicDevice` C++ class rather than through the attribute directly.

        Example:
        ```mlir
        #magic.device<name = "two-trap", time_unit_ns = 1000, initial_occupancies = [2, 1], traps = [#trap, #trap]>
        ```
    }];

  let parameters = (ins
    StringRefParameter<"human-readable device name">:$name,
    "int64_t":$time_unit_ns,
    ArrayRefParameter<"int64_t", "ions loaded at program start, per trap">:$initial_occupancies,
    QCC_ArrayRefParameter<"::qcc::magic::TrapAttr", "the traps, index = trap id">:$traps
  );

  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}

#endif // INCLUDE_QCC_DIALECT_MAGIC_IR_MAGICATTRS_TD_
