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
      %q1 = qco.h %q0 : !qco.qubit -> !qco.qubit
      ```

      becomes

      ```mlir
      %qs = vector.from_elements %q0 : vector<1x!qco.qubit>
      %hs = qvec.single h %qs : vector<1x!qco.qubit>
      %q1 = vector.extract %hs[0] : !qco.qubit from vector<1x!qco.qubit>
      ```

      Similar for pairs and measurements.

      `qco.static` is kept as the source of qubits, and `qco.sink` is erased. Gates that cannot be
      legalized make the pass fail. Note that legality here is the `qvec` gate set, not any one
      machine's: a gate this pass accepts may still be rejected further down by a target that cannot
      execute it.

      `qco.if` becomes `scf.if`. The qubits going in stand in for the block arguments, and the qubit
      results are kept, so that an operation using one stays behind the `if`.
   }];

  let dependentDialects = [
    "mlir::qco::QCODialect",
    "mlir::scf::SCFDialect",
    "mlir::vector::VectorDialect",
    "qcc::qvec::QVecDialect"
  ];
}
