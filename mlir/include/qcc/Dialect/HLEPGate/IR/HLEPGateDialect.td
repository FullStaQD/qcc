// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_HLEPGATE_IR_HLEPGATEDIALECT_TD_
#define INCLUDE_QCC_DIALECT_HLEPGATE_IR_HLEPGATEDIALECT_TD_

include "mlir/IR/DialectBase.td"
include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// HLEPGate dialect
//===----------------------------------------------------------------------===//

def HLEPGateDialect : Dialect {
    let summary = "Gate-level normal form of PrelimHLEP programs.";
    let description = [{
        A small set of gate-level operations acting on PrelimHLEP's quantum
        types. It is the target of `--prelim-hlep-lin-to-gates`, which peels
        gates out of `prelimhlep.lin` ops until none are left, and the source
        of `--prelim-hlep-to-qco`.

        A single qubit is a `!prelimhlep.lin<i1>` value, so the halo
        linearity checker of PrelimHLEP covers these ops as well. Gates act in
        the computational (Z) basis; X- and Y-basis values are reached through
        `prelimhlep.base_change`, which is the identity on the state.

        Every op denotes a partial linearization, i.e. a `prelimhlep.lin` op
        with a fixed body.

        Example:
        ```mlir
        %q0 = hlepgate.alloc
        %q1 = hlepgate.single h %q0
        %c, %t = hlepgate.single x %q2 ctrl(%q1)
        %q3, %bit = hlepgate.measure %t
        hlepgate.sink %q3
        ```
    }];

    let name = "hlepgate";
    let cppNamespace = "::qcc::hlepgate";

    // `!prelimhlep.lin<...>` appears in our operations' assembly.
    let dependentDialects = ["::qcc::prelimhlep::PrelimHLEPDialect"];

    let useDefaultAttributePrinterParser = 1; // needed by the gate-kind attribute.
}

#endif // INCLUDE_QCC_DIALECT_HLEPGATE_IR_HLEPGATEDIALECT_TD_
