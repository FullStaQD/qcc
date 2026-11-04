// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def ConvertQCOToQVec : Pass<"convert-qco-to-qvec", "mlir::ModuleOp"> {
  let summary = "Replaces scalar QCO ops with QVec ops.";

  let description = [{
      The rewritten gates use single-width vectors. Packing independent gates into wider operations
      is `qvec-merge`'s job.

      Every gate gets wrapped between `vector.from_elements` and `vector.extract` ops. For example

      ```mlir
      %q1 = qco.rz(%theta) %q0 : !qco.qubit -> !qco.qubit
      ```

      becomes

      ```mlir
      %qs = vector.from_elements %q0 : vector<1x!qcc.qubit>
      %ts = vector.from_elements %theta : vector<1xf64>
      %rs = qvec.single rz(%ts) %qs : vector<1xf64>, vector<1x!qcc.qubit>
      %q1 = vector.extract %rs[0] : !qcc.qubit from vector<1x!qcc.qubit>
      ```

      Similar for pairs, measurements and resets. The qubits become `!qcc.qubit`: the `qco.static` ops of a function
      turn into one `qcc.static` at its start, which takes each index once.

      Gates that cannot be legalized make the pass fail; `qco.id` is dropped and `qco.sink` is erased. Not supported:
      functions that take or return qubits, and a `qco.if` that binds a qubit straight from its `qco.static`, as the
      `scf.if` would use it in both branches.
   }];

  let dependentDialects = [
    "mlir::qco::QCODialect",
    "mlir::scf::SCFDialect",
    "mlir::vector::VectorDialect",
    "qcc::QccDialect",
    "qcc::qvec::QVecDialect"
  ];
}
