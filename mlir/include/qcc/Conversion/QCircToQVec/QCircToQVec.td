// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def ConvertQCircToQVec : Pass<"convert-qcirc-to-qvec", "mlir::func::FuncOp"> {
  let summary = "Converts `qcirc` ops into `qvec` ops.";

  let description = [{
      Turns `!qcc.qubit` into a vector of one qubit, `vector<1x!qcc.qubit>`, and each `qcirc` op into the `qvec` op of
      the same name, gate kind and basis. Packing independent ops into wider ones is `qvec-merge`'s job. Moreover

      - The results of `qcc.static` stay scalar. Each one in use is packed by a `vector.from_elements` behind it.
      - Each angle is packed into a `vector<1xf64>`, and each measured bit is taken out by `vector.extract`.
      - `qcf.if` becomes `scf.if`, which captures the bound qubits. Its qubit results stay, so that later ops on these
        qubits stay ordered after it.

      Precondition: only `qcc.static`, `qcirc` and `qcf` ops use qubits.

      Example:

      ```mlir
      %q:2 = qcc.static [0, 1] : !qcc.qubit
      %q0 = qcirc.single rz(%theta) %q#0 : f64, !qcc.qubit
      %q0_1, %bit = qcirc.measure z %q0 : !qcc.qubit -> i1
      %q1 = qcf.if %bit (%a = %q#1) -> (!qcc.qubit) {
        %a_1 = qcirc.single x %a : !qcc.qubit
        qcf.yield %a_1 : !qcc.qubit
      }
      ```

      becomes

      ```mlir
      %q:2 = qcc.static [0, 1] : !qcc.qubit
      %v1 = vector.from_elements %q#1 : vector<1x!qcc.qubit>
      %v0 = vector.from_elements %q#0 : vector<1x!qcc.qubit>
      %ts = vector.from_elements %theta : vector<1xf64>
      %v0_1 = qvec.single rz(%ts) %v0 : vector<1xf64>, vector<1x!qcc.qubit>
      %v0_2, %bits = qvec.measure z %v0_1 : vector<1x!qcc.qubit> -> vector<1xi1>
      %bit = vector.extract %bits[0] : i1 from vector<1xi1>
      %v1_1 = scf.if %bit -> (vector<1x!qcc.qubit>) {
        %a_1 = qvec.single x %v1 : vector<1x!qcc.qubit>
        scf.yield %a_1 : vector<1x!qcc.qubit>
      } else {
        scf.yield %v1 : vector<1x!qcc.qubit>
      }
      ```
  }];

  let dependentDialects = [
    "mlir::scf::SCFDialect",
    "mlir::vector::VectorDialect",
    "qcc::qvec::QVecDialect"
  ];
}
