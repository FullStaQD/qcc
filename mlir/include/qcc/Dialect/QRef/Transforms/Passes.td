// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QREF_TRANSFORMS_PASSES_TD_
#define INCLUDE_QCC_DIALECT_QREF_TRANSFORMS_PASSES_TD_

include "mlir/Pass/PassBase.td"

def QRefAssignQubits : Pass<"qref-assign-qubits", "mlir::ModuleOp"> {
  let summary = "Assigns a static qubit to each allocated qubit.";

  let description = [{
      Replaces each `qcc.alloc` by a `qcc.static_ref` per qubit, and erases each `qcc.dealloc`. An array becomes a
      `tensor.from_elements` of its qubits, so that a canonicalizer can fold extracts with a constant index.

      Each allocated qubit gets a static index that no other live qubit has, and never one that an existing
      `qcc.static_ref` of the function already names. An allocation can reuse qubits that a dealloc dominating it freed,
      and resets them to |0⟩. An allocation in a sequential loop (e.g. `scf.for`, `scf.while`) resets all its qubits.
      Which indices the qubits get is a heuristic.

      Each function of the module is taken to be a program on its own.

      Preconditions:
      - Each allocation has a constant size.
      - Each `qcc.dealloc` frees the result of a `qcc.alloc`, possibly through `tensor.cast`.
      - An allocation in a sequential loop is freed by a `qcc.dealloc` in its block.
      - Nothing calls or refers to a function that allocates or names qubits (with `qcc.alloc` or `qcc.static_ref`).

      Example:

      ```mlir
      %c2 = arith.constant 2 : index
      %r = qcc.alloc %c2 : tensor<?x!qcc.qubit_ref>
      // ... do something with %r.
      qcc.dealloc %r : tensor<?x!qcc.qubit_ref>
      %q = qcc.alloc : !qcc.qubit_ref
      qref.single h %q : !qcc.qubit_ref
      ```

      becomes, for instance,

      ```mlir
      %q0 = qcc.static_ref [0] : !qcc.qubit_ref
      %q1 = qcc.static_ref [1] : !qcc.qubit_ref
      %a = tensor.from_elements %q0, %q1 : tensor<2x!qcc.qubit_ref>
      %r = tensor.cast %a : tensor<2x!qcc.qubit_ref> to tensor<?x!qcc.qubit_ref>
      // ... do something with %r.
      // Note that qubits 0 and 1 are free to reuse now (due to dealloc). We use a reset to reinitialize it.
      %q = qcc.static_ref [0] : !qcc.qubit_ref
      qref.reset z %q : !qcc.qubit_ref
      qref.single h %q : !qcc.qubit_ref
      ```
  }];

  let dependentDialects = [
    "mlir::tensor::TensorDialect",
    "qcc::QccDialect",
    "qcc::qref::QRefDialect"
  ];
}

#endif // INCLUDE_QCC_DIALECT_QREF_TRANSFORMS_PASSES_TD_
