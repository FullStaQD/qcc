// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QREF_IR_QREFDIALECT_TD_
#define INCLUDE_QCC_DIALECT_QREF_IR_QREFDIALECT_TD_

include "mlir/IR/DialectBase.td"

//===----------------------------------------------------------------------===//
// QRef dialect
//===----------------------------------------------------------------------===//

def QRef_Dialect : Dialect {
    let summary = "Quantum circuits dialect in memory semantics.";
    let description = [{
        The `qref` dialect represents the traditional quantum circuit model in memory semantics. Its operations act in
        place on their qubit operands. References may be copied, so standard control flow such as `scf.if` uses them
        directly.

        The dialect does not model a global phase: gates are equal if they agree up to a global phase, and a lowering
        into `qref` may drop one.

        Example:
        ```mlir
        %q0, %q1 = qcc.static_ref [0, 1] : !qcc.qubit_ref

        // A Bell pair, then both qubits are measured.
        qref.single h %q0 : !qcc.qubit_ref
        qref.pair cx %q0, %q1 : !qcc.qubit_ref
        %m0 = qref.measure z %q0 : !qcc.qubit_ref -> i1
        %m1 = qref.measure z %q1 : !qcc.qubit_ref -> i1

        // Flips %q1 back to |0⟩ if it was measured as |1⟩.
        scf.if %m1 {
          qref.single x %q1 : !qcc.qubit_ref
        }
        ```
    }];

    let name = "qref";
    let cppNamespace = "::qcc::qref";

    // `!qcc.qubit_ref` and the gate-kind attributes appear in our operations' assembly.
    let dependentDialects = ["::qcc::QccDialect"];
}

#endif // INCLUDE_QCC_DIALECT_QREF_IR_QREFDIALECT_TD_
