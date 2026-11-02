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
  let summary = "Converts `qref` ops into `qcirc` ops.";

  let description = [{
      Turns `!qcc.qubit_ref` into `!qcc.qubit`. Moreover

      - All `qcc.static_ref` become a single `qcc.static` near the entry of the function.
      - An `scf` op that acts on qubits becomes a `qcf` op.

      Preconditions:
      - The function does not call other functions.
      - Every qubit is a static qubit: it comes from `qcc.static_ref`, not from `qcc.alloc`, an argument or an array.
        Only gates, measurements and resets use it.
      - Qubit ops sit at the top level of the function or inside `scf` regions, and the function has a single block.

      TODO: Some control flow like `scf.for` is not yet supported. Needs to be added.

      Functions without qubit references are left alone.

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
