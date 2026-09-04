// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QVEC_TRANSFORMS_PASSES_TD_
#define INCLUDE_QCC_DIALECT_QVEC_TRANSFORMS_PASSES_TD_

include "mlir/Pass/PassBase.td"

def QVecMerge : Pass<"qvec-merge", "mlir::ModuleOp"> {
  let summary = "Merges independent `qvec` operations into wider ones.";

  let description = [{
      Merges `qvec` operations that carry the same gate and act on disjoint qubits into one operation over the union
      of their qubits. Merges only happen within the same block.

      Cost model: the vectorization factor VF, i.e. the number of elements in one operation, is made as large as the
      option `max-vf` allows.

      TODO: What this deliberately ignores is that a target may charge for a change of VF between two instructions,
      which a uniform-VF policy would trade instruction count for. We might want to update the cost model accordingly in
      the future.

      Example:

      ```mlir
      // Assuming %v0, %v1, %v2 are known to refer to disjoint sets of qubits.
      %h0 = qvec.single h %v0 : vector<4x!qco.qubit>
      %x1 = qvec.single x %v1 : vector<3x!qco.qubit> // despite obstacle we can still merge the hadamards
      %h2 = qvec.single h %v2 : vector<2x!qco.qubit>
      ```

      turns into

      ```mlir
      %5 = qvec.single h %4 : vector<6x!qco.qubit>
      %6 = qvec.single x %3 : vector<3x!qco.qubit>
      ```
  }];

  let options = [
    Option<"maxVF", "max-vf", "unsigned", /*default=*/"0",
           "Cap on the number of elements per operation; 0 leaves it unbounded; pre-existing wider operations left alone.">
  ];

  let dependentDialects = [
    "mlir::vector::VectorDialect",
    "qcc::qvec::QVecDialect"
  ];
}

#endif // INCLUDE_QCC_DIALECT_QVEC_TRANSFORMS_PASSES_TD_
