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

      Similar for pairs and measurements. Angles travel the same way, as `vector<1xf64>` built by
      `vector.from_elements` (a constant angle stays foldable):

      ```mlir
      %q1 = qco.rz(%theta) %q0 : !qco.qubit -> !qco.qubit
      ```

      becomes

      ```mlir
      %qs = vector.from_elements %q0 : vector<1x!qco.qubit>
      %ts = vector.from_elements %theta : vector<1xf64>
      %rs = qvec.single rz(%ts) %qs : vector<1x!qco.qubit>, vector<1xf64>
      %q1 = vector.extract %rs[0] : !qco.qubit from vector<1x!qco.qubit>
      ```

      Gates without a `qvec` kind of their own are mapped to one they equal up to a global phase, which
      `qvec` does not model: `qco.p(theta)` becomes `single rz(theta)` and a top-level `qco.gphase` is
      erased. A `qco.ctrl` with one control maps to a `pair` if its body is a single `x`, `y`, `z` or
      `p(theta)` (`cx`, `cy`, `cz`, `cp(theta)`); with no targets and a `gphase(theta)` body it becomes
      `single rz(theta)` on the control. Inside a control region only exact identities are used, so e.g.
      `ctrl { rz }` is rejected (it is not `cp`).

      `qco.static` is kept as the source of qubits, and `qco.sink` is erased. Gates that cannot be
      legalized make the pass fail. Note that legality here is the `qvec` gate set, not any one
      machine's: a gate this pass accepts may still be rejected further down by a target that cannot
      execute it.
   }];

  let dependentDialects = [
    "mlir::qco::QCODialect",
    "mlir::vector::VectorDialect",
    "qcc::qvec::QVecDialect"
  ];
}
