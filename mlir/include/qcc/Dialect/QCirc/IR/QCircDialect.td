// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCIRC_IR_QCIRCDIALECT_TD_
#define INCLUDE_QCC_DIALECT_QCIRC_IR_QCIRCDIALECT_TD_

include "mlir/IR/DialectBase.td"
include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// QCirc dialect
//===----------------------------------------------------------------------===//

def QCirc_Dialect : Dialect {
    let summary = "Quantum circuits dialect in value semantics.";
    let description = [{
        The `qcirc` dialect represents the traditional quantum circuit model in value semantics. Qubit values are
        affine, which the `SingleUseQubits` trait on each operation enforces.

        The dialect does not model a global phase: gates are equal if they agree up to a global phase, and a lowering
        into `qcirc` may drop one.

        Example:
        ```mlir
        %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
        // A Bell pair, then both qubits are measured.
        %h = qcirc.single h %q0 : !qcc.qubit
        %c, %t = qcirc.pair cx %h, %q1 : !qcc.qubit
        %c_out, %m0 = qcirc.measure z %c : !qcc.qubit -> i1
        %t_out, %m1 = qcirc.measure z %t : !qcc.qubit -> i1
        ```
    }];

    let name = "qcirc";
    let cppNamespace = "::qcc::qcirc";

    // `!qcc.qubit` appears in our operations' assembly.
    let dependentDialects = ["::qcc::QccDialect"];

    let useDefaultTypePrinterParser = 0;      // set to 1 once we define types of our own.
    let useDefaultAttributePrinterParser = 1; // needed by the gate-kind attributes.
}

#endif // INCLUDE_QCC_DIALECT_QCIRC_IR_QCIRCDIALECT_TD_
