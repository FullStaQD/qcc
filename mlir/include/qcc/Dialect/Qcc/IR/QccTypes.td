// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCC_IR_QCCTYPES_TD_
#define INCLUDE_QCC_DIALECT_QCC_IR_QCCTYPES_TD_

include "qcc/Dialect/Qcc/IR/QccDialect.td"

include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/BuiltinTypeInterfaces.td"

//===----------------------------------------------------------------------===//
// Qcc types
//===----------------------------------------------------------------------===//

def Qcc_QubitType : TypeDef<Qcc_Dialect, "Qubit", [VectorElementTypeInterface]> {
  let mnemonic = "qubit";
  let summary = "qubit value";
  let description = [{
        A value of type `!qcc.qubit` denotes one qubit at one program point. An operation that acts on a qubit consumes
        the value and returns the qubit as a new value.

        The type is *affine*: each value may be consumed at most once on any execution path (no-cloning). A value that
        is never consumed is discarded, which traces the qubit out.

        A vector of qubits, e.g. `vector<2x!qcc.qubit>`, holds its qubits, and the discipline applies to each of them.
        Taking an element out (`vector.extract`) yields the qubit, not a copy, and an operation that takes the vector
        as a whole consumes all of its qubits. So once a qubit has been consumed through an element, the vector must
        not be consumed as a whole, and the same element must not be taken out and consumed twice. To act on some of
        the qubits, take the vector apart and build a new one from the results (`vector.from_elements`).

        Example:
        ```mlir
        %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
        %qs = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
        ```
    }];
}

//===----------------------------------------------------------------------===//
// Qcc type constraints
//===----------------------------------------------------------------------===//

// What a qubit lane carries: `!qcc.qubit` or a vector of them.
def Qcc_QubitOrQubitVector : Type<CPred<"::qcc::isQubitOrQubitVector($_self)">, "qubit or vector of qubits">;

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCTYPES_TD_
