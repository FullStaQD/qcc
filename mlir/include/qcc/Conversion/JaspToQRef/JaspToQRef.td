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

      - `!jasp.Qubit` becomes `!qcc.qubit_ref` and `!jasp.QubitArray` an array `tensor<?x!qcc.qubit_ref>`.
        `!jasp.QuantumState` is dropped, also from function signatures, and so are `jasp.create_quantum_kernel` and
        `jasp.consume_quantum_kernel` (its result becomes `true`).
      - A rank-0 tensor, e.g. `tensor<i64>`, becomes its element type wherever possible.
      - `jasp.create_qubits` becomes `qcc.alloc`, `jasp.delete_qubits` `qcc.dealloc`, `jasp.get_qubit`
        `tensor.extract`, and `jasp.get_size` `tensor.dim`.
      - A gate becomes the `qref.single` or `qref.pair` of the same name, `s_dg` and `t_dg` become `sdg` and `tdg`.
        `p` becomes `rz`, and `u3(theta, phi, lambda)` becomes `u_zyz(lambda, theta, phi)`: they agree up to a global
        phase. `id` and `gphase` are dropped.
      - `jasp.measure` and `jasp.reset` become `qref.measure z` and `qref.reset z`. On an array they become an `scf.for`
        over its qubits, and the measurement packs the outcomes into an `i64`, the one of qubit `i` into bit `i`.

      Any other gate, e.g. `xxyy`, and any other `jasp` op make the pass fail: it does not decompose gates.

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
