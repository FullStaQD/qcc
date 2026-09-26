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
      %qs = vector.from_elements %q0 : vector<1x!qco.qubit>
      %ts = vector.from_elements %theta : vector<1xf64>
      %rs = qvec.single rz(%ts) %qs : vector<1x!qco.qubit>, vector<1xf64>
      %q1 = vector.extract %rs[0] : !qco.qubit from vector<1x!qco.qubit>
      ```

      Similar for pairs and measurements.

      Gates which cannot be translated 1:1 are decomposed if possible. Gates that cannot be legalized make the pass
      fail. `qco.static` is kept as the source of qubits, and `qco.sink` is erased.
   }];

  let dependentDialects = [
    "mlir::qco::QCODialect",
    "mlir::vector::VectorDialect",
    "qcc::qvec::QVecDialect"
  ];
}
