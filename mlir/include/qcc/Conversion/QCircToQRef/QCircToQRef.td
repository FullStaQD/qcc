// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def ConvertQCircToQRef : Pass<"convert-qcirc-to-qref", "mlir::func::FuncOp"> {
  let summary = "Converts `qcirc` ops into `qref` ops, and `qcf.if` into `scf.if`.";

  let description = [{
      Turns qubit values into references to their qubits. Every `!qcc.qubit` value of a qubit becomes the reference
      to it:

      - `qcc.static` becomes `qcc.static_ref` with the same indices. The function is taken to be a program on its own,
        so its qubits are in |0⟩ when it starts either way.
      - Each gate, measurement and reset becomes its `qref` counterpart. Its qubit results are the references it acts
        on.
      - `qcf.if` becomes `scf.if` with the classical results only. Its bindings and its qubit results are the bound
        references.

      Vectors of qubits are not supported.

      Example:

      ```mlir
      %q:2 = qcc.static [0, 1] : !qcc.qubit
      %q0, %bit = qcirc.measure z %q#0 : !qcc.qubit -> i1
      %q1 = qcf.if %bit (%a = %q#1) -> (!qcc.qubit) {
        %a_1 = qcirc.single x %a : !qcc.qubit
        qcf.yield %a_1 : !qcc.qubit
      }
      ```

      becomes

      ```mlir
      %q:2 = qcc.static_ref [0, 1] : !qcc.qubit_ref
      %bit = qref.measure z %q#0 : !qcc.qubit_ref -> i1
      scf.if %bit {
        qref.single x %q#1 : !qcc.qubit_ref
      }
      ```
  }];

  let dependentDialects = [
    "mlir::scf::SCFDialect",
    "qcc::QccDialect",
    "qcc::qref::QRefDialect"
  ];
}
