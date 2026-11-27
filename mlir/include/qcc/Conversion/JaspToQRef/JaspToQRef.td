// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def ConvertJaspToQRef : Pass<"convert-jasp-to-qref", "mlir::ModuleOp"> {
  let summary = "Converts Qrisp's `jasp` dialect into `qref`.";

  let description = [{
      Converts the `jasp` ops (see https://qrisp.eu/reference/Jasp/MLIR%20Interface.html) into `qref`, `qcc` and
      builtin ops. Both act on qubits in place, so the ops map essentially one to one:

      - `!jasp.Qubit` becomes `!qcc.qubit_ref` and `!jasp.QubitArray` a tensor thereof.
      - A gate becomes the corresponding `qref.single` or `qref.pair`. `id` and `gphase` are dropped.
      - `jasp.measure` and `jasp.reset` become `qref.measure z` and `qref.reset z`. On an array they become a loop over
        its qubits.
      - Dropped: `!jasp.QuantumState` as well as its creator `jasp.create_quantum_kernel` and consumer
        `jasp.consume_quantum_kernel` (its result becomes `true`).
      - A rank-0 tensor `tensor<SCALAR>` becomes `SCALAR` (e.g. `i64`) wherever possible.
      - `jasp.create_qubits` becomes `qcc.alloc`, `jasp.delete_qubits` `qcc.dealloc`, `jasp.get_qubit`
        `tensor.extract`, and `jasp.get_size` `tensor.dim`.

      Unknown gates and `jasp` ops make the pass fail. Gates are not decomposed.

      TODO: Yes more than 64 qubits being measured silently discards measurement results. This is a known issue of
      Qrisp's semantics. We have to find a way to deal with this: User warning, error, etc. There is a way to handle
      more than 64 qubits but it requires the user to use big integers (see
      https://qrisp.eu/reference/Jasp/Scalable%20Integer%20Type.html).

      Example:

      ```mlir
      %q, %s1 = jasp.create_qubits %n, %s0 : !jasp.QuantumState, tensor<i64> -> !jasp.QubitArray, !jasp.QuantumState
      %q0 = jasp.get_qubit %q, %i : !jasp.QubitArray, tensor<i64> -> !jasp.Qubit
      %s2 = jasp.quantum_gate "h" (%q0), %s1 : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
      ```

      becomes

      ```mlir
      %n_i64 = tensor.extract %n[] : tensor<i64>
      %n_index = arith.index_cast %n_i64 : i64 to index
      %q = qcc.alloc %n_index : tensor<?x!qcc.qubit_ref>
      %i_i64 = tensor.extract %i[] : tensor<i64>
      %i_index = arith.index_cast %i_i64 : i64 to index
      %q0 = tensor.extract %q[%i_index] : tensor<?x!qcc.qubit_ref>
      qref.single h %q0 : !qcc.qubit_ref
      ```
  }];

  let dependentDialects = [
    "mlir::arith::ArithDialect",
    "mlir::scf::SCFDialect",
    "mlir::tensor::TensorDialect",
    "qcc::QccDialect",
    "qcc::qref::QRefDialect"
  ];
}
