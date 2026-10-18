// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCF_IR_QCFDIALECT_TD_
#define INCLUDE_QCC_DIALECT_QCF_IR_QCFDIALECT_TD_

include "mlir/IR/DialectBase.td"

//===----------------------------------------------------------------------===//
// QCF dialect
//===----------------------------------------------------------------------===//

def QCF_Dialect : Dialect {
    let summary = "Quantum-aware structured control flow in value semantics.";
    let description = [{
        The `qcf` dialect is the analog of `scf` for code acting on qubits in value semantics, such as the `qcirc`
        dialect. Its operations are qubit scopes (`QubitScope` trait): a qubit enters one of their regions only as an
        argument of the entry block, a *binding*, never by capture. Each binding leaves the operation as the result
        of the same position, so the operation looks like one big gate from the outside.

        Example:
        ```mlir
        %q0, %q1 = qcc.static [0, 1] : !qcc.qubit

        %h = qcirc.single h %q0 : !qcc.qubit
        %m0, %bit = qcirc.measure z %h : !qcc.qubit -> i1

        // Flips %q1 if %q0 was measured as |1⟩.
        %q1_out = qcf.if %bit (%q = %q1) -> !qcc.qubit {
          %x = qcirc.single x %q : !qcc.qubit
          qcf.yield %x : !qcc.qubit
        }
        ```
    }];

    let name = "qcf";
    let cppNamespace = "::qcc::qcf";

    let dependentDialects = ["::qcc::QccDialect"];
}

#endif // INCLUDE_QCC_DIALECT_QCF_IR_QCFDIALECT_TD_
