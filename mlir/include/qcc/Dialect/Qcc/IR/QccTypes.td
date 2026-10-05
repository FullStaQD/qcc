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

// A vector element (`vector<4x!qcc.qubit>`), but deliberately no memref element: the type has value semantics.
def Qcc_QubitType : TypeDef<Qcc_Dialect, "Qubit", [VectorElementTypeInterface]> {
  let mnemonic = "qubit";
  let summary = "qubit value";
  let description = [{
        A value of type `!qcc.qubit` denotes one qubit at one program point. An operation that acts on a qubit consumes
        the value and returns the qubit as a new value.

        The type is *affine*: each value may be consumed at most once on any execution path (no-cloning). A value that
        is never consumed is discarded, which traces the qubit out. See the dialect description on how this is enforced.

        Example:
        ```mlir
        %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
        %qs = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
        ```
    }];
}

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCTYPES_TD_
