// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCC_IR_QCCOPS_TD_
#define INCLUDE_QCC_DIALECT_QCC_IR_QCCOPS_TD_

include "qcc/Dialect/Qcc/IR/QccDialect.td"
include "qcc/Dialect/Qcc/IR/QccInterfaces.td"
include "qcc/Dialect/Qcc/IR/QccTypes.td"

include "mlir/IR/CommonAttrConstraints.td"
include "mlir/IR/OpBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// Qcc operations
//===----------------------------------------------------------------------===//

// No memory effects, but deliberately not `Pure`: qubit values must never be duplicated.
def Qcc_StaticOp : Op<Qcc_Dialect, "static", [NoMemoryEffect, Qcc_SingleUseQubits]> {
  let summary = "the qubits of a function, by static index";
  let description = [{
        Creates the qubits a function works on, one result per index, each initialized in |0⟩. The indices are
        non-negative and distinct, but need not be dense or sorted.

        The op is the only source of qubits. It sits directly in a `func.func`, and a function holds at most one of
        them.

        Example:
        ```mlir
        %q0, %q1, %q3 = qcc.static [0, 1, 3] : !qcc.qubit
        ```
    }];

  let arguments = (ins DenseI64ArrayAttr:$indices);
  let results = (outs Variadic<Qcc_QubitType>:$qubits);

  let assemblyFormat = [{
        $indices attr-dict `:` custom<StaticTypes>(type($qubits), ref($indices))
    }];

  let builders = [
    // One qubit per entry of `indices`.
    OpBuilder<(ins "::llvm::ArrayRef<int64_t>":$indices)>
  ];

  let hasVerifier = 1;
}

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCOPS_TD_
