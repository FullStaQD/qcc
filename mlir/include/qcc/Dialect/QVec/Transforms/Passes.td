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

// FIXME: update summary and description at the end.

def QVecMerge : Pass<"qvec-merge", "mlir::ModuleOp"> {
  let summary = "Packs independent `qvec` operations into wider ones.";

  let description = [{
      Merges `qvec` operations that carry the same gate and act on independent qubits into one
      operation over the union of their qubits. One `qvec` operation is meant to be one machine
      instruction -- on HiSEP-Q, one QV instruction -- so this is what turns a gate-at-a-time
      program into a vectorized one.

      Every operation is assigned a layer, `layer(op) = 1 + max(layer(predecessors))`, where the
      predecessors are the operations that produced the qubits it consumes. Operations in the
      same layer are by construction independent, hence commute, hence may be merged. Within a
      layer they are bucketed by gate -- one `qvec.single h`, one `qvec.single x`, one
      `qvec.pair cx`, one `qvec.mz`, and so on -- and each bucket is packed greedily in
      program order.

      Cost model: the vectorization factor VF, i.e. the number of elements in one operation, is
      made as large as `max-vf` allows, because fewer, wider operations mean fewer instructions.
      What this deliberately ignores is that a target may charge for a change of VF between two
      instructions, which a uniform-VF policy would trade instruction count for.
      TODO: Weigh reconfiguration against instruction count once there are numbers to weigh with.

      How many qubits one instruction can name is a property of the target, which this pass knows
      nothing about: `max-vf` is the only bound, and deriving it is the caller's job. The default
      of 0 leaves VF unbounded, so a lowering further down the pipeline is what rejects an
      operation too wide for the machine it targets.

      Merging moves operations, which their `MemRead`/`MemWrite` effects nominally forbid. Those
      effects are a conservative backstop for passes that do not know what a qubit is; here the
      layering establishes that the operations being reordered touch disjoint qubits, and gates on
      disjoint qubits commute.

      A group is cut short when the next operation would exceed VF, would repeat a qubit the group
      already names (which well-formed value-semantics IR cannot do, so this only guards against
      malformed input -- notably `qvec.pair`, where controls and targets must not overlap
      across the whole group), or when its operands cannot be made available where the merged
      operation goes.

      Operations never merge across blocks or region boundaries.

      Packing takes a qubit vector apart element by element and puts it back together, so the pass
      finishes by running the `vector` canonicalization patterns over the module. Where a merged
      group reads a whole predecessor result back in order that restores the direct operand -- one
      operation threading into the next, with no glue in between -- and one-element vectors come
      out as `vector.broadcast` rather than `vector.from_elements`. Nothing depends on the cleanup
      running: `qvec::getQubitElement` sees through either form.
  }];

  let options = [
    Option<"maxVF", "max-vf", "unsigned", /*default=*/"0",
           "Cap on the number of elements per operation; 0 leaves it unbounded.">
  ];

  let dependentDialects = [
    "mlir::vector::VectorDialect",
    "qcc::qvec::QVecDialect"
  ];
}

#endif // INCLUDE_QCC_DIALECT_QVEC_TRANSFORMS_PASSES_TD_
