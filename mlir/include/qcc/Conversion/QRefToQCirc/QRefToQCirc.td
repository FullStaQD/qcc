// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def ConvertQRefToQCirc : Pass<"convert-qref-to-qcirc", "mlir::func::FuncOp"> {
  let summary = "Converts `qref` ops into `qcirc` ops, and `scf.if` around them into `qcf.if`.";

  let description = [{
      Turns the qubit references of a function into qubit values. A `qcc.static` at the top of the function creates
      every static qubit that a `qcc.static_ref` in it names, and the static qubit with index N is the same qubit in
      both. Each gate, measurement and reset becomes its `qcirc` counterpart, which consumes the current value of its
      qubits and returns their next one. An `scf.if` with qubit ops inside becomes a `qcf.if` that binds the qubits its
      regions act on, in the order of their indices; its classical results follow the qubits.

      The function is taken to be a program on its own: its qubits are in |0⟩ when it starts, as `qcc.static` states.
      A `qcc.static_ref` does not state this, but the qubits are in |0⟩ at the start of a program.

      Functions without qubit references are left alone. A function with them must meet these preconditions, or the
      pass fails:
      - It is self-contained: it calls no function.
      - Every qubit is a static qubit: it comes from `qcc.static_ref`, not from `qcc.alloc`, an argument or an array.
        Only gates, measurements and resets use it.
      - Qubit ops sit at the top level of the function or inside `scf.if`, and the function has a single block.

      Example:

      ```mlir
      %q0, %q1 = qcc.static_ref [0, 1] : !qcc.qubit_ref
      qref.single h %q0 : !qcc.qubit_ref
      %bit = qref.measure z %q0 : !qcc.qubit_ref -> i1
      scf.if %bit {
        qref.single x %q1 : !qcc.qubit_ref
      }
      ```

      becomes

      ```mlir
      %q:2 = qcc.static [0, 1] : !qcc.qubit
      %q0 = qcirc.single h %q#0 : !qcc.qubit
      %q0_1, %bit = qcirc.measure z %q0 : !qcc.qubit -> i1
      %q1 = qcf.if %bit (%a = %q#1) -> (!qcc.qubit) {
        %a_1 = qcirc.single x %a : !qcc.qubit
        qcf.yield %a_1 : !qcc.qubit
      }
      ```
  }];

  let dependentDialects = [
    "qcc::QccDialect",
    "qcc::qcf::QCFDialect",
    "qcc::qcirc::QCircDialect"
  ];
}
