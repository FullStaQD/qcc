// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def ConvertQCToQRef : Pass<"convert-qc-to-qref", "mlir::func::FuncOp"> {
  let summary = "Converts `qc` ops into `qref` ops.";

  let description = [{
      Bridges the `qc` IR of the Qrisp lowering to `qref`. Both act on qubits in place, so the ops map one to one and
      every `!qc.qubit` becomes a `!qcc.qubit_ref`:

      - `qc.static N` becomes `qcc.static_ref [N]`.
      - A gate becomes the `qref.single` or `qref.pair` of the same name. `p` becomes `rz`, and `u(theta, phi, lambda)`
        becomes `u_zyz(lambda, theta, phi)`: they agree up to a global phase.
      - `qc.ctrl` with one control around a single `x`, `y`, `z`, `p` or `rz` becomes `cx`, `cy`, `cz`, `cp` or `crz`.
        Around a single `gphase`, it becomes `rz` on the control (a controlled phase is a relative phase).
      - `qc.gphase` and `qc.id` are dropped.
      - `qc.measure` and `qc.reset` become `qref.measure z` and `qref.reset z`.

      Any other `qc` op makes the pass fail: it does not decompose gates.

      Example:

      ```mlir
      %q0 = qc.static 0 : !qc.qubit
      %q1 = qc.static 1 : !qc.qubit
      qc.p(%theta) %q0 : !qc.qubit
      qc.ctrl(%q0) targets (%t = %q1) {
        qc.x %t : !qc.qubit
        qc.yield
      } : {!qc.qubit}, {!qc.qubit}
      %bit = qc.measure %q1 : !qc.qubit -> i1
      ```

      becomes

      ```mlir
      %q0 = qcc.static_ref [0] : !qcc.qubit_ref
      %q1 = qcc.static_ref [1] : !qcc.qubit_ref
      qref.single rz(%theta) %q0 : f64, !qcc.qubit_ref
      qref.pair cx %q0, %q1 : !qcc.qubit_ref
      %bit = qref.measure z %q1 : !qcc.qubit_ref -> i1
      ```
  }];

  let dependentDialects = [
    "qcc::QccDialect",
    "qcc::qref::QRefDialect"
  ];
}
