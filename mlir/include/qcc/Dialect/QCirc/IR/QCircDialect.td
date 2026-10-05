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
    let summary = "Quantum circuits on individual qubits: gates, measurements and resets.";
    let description = [{
        The `qcirc` dialect expresses a quantum circuit one operation at a time: gates, measurements and resets on
        individual qubits (`!qcc.qubit`). It leaves control flow to other dialects, and gates across whole vectors of
        qubits to `qvec`.

        The dialect has **value semantics**: an operation consumes its qubits and returns them as new values. Qubit
        values are affine, which every operation enforces on the qubits it touches (see the `qcc` dialect). In
        particular the qubits of one operation are distinct.

        The operations are free of memory effects, but not `Pure`: an operation whose results are unused may be
        erased, but folding or hoisting must never duplicate a qubit value.

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
