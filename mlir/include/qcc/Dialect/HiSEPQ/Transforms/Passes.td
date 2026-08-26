// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_HISEPQ_TRANSFORMS_PASSES_TD_
#define INCLUDE_QCC_DIALECT_HISEPQ_TRANSFORMS_PASSES_TD_

include "mlir/Pass/PassBase.td"

// FIXME: update summary and description at the end.

def VectorizeHiSEPQ : Pass<"hisepq-vectorize", "mlir::ModuleOp"> {
  let summary = "Packs independent HiSEP-Q operations into wider ones.";

  let description = [{
      Merges `hisepq` operations that carry the same gate and act on independent qubits into one
      operation over the union of their qubits. One `hisepq` operation is one QV instruction, so
      this is what turns a gate-at-a-time program into a vectorized one.

      Every operation is assigned a layer, `layer(op) = 1 + max(layer(predecessors))`, where the
      predecessors are the operations that produced the qubits it consumes. Operations in the
      same layer are by construction independent, hence commute, hence may be merged. Within a
      layer they are bucketed by gate -- one `hisepq.single h`, one `hisepq.single x`, one
      `hisepq.pair cx`, one `hisepq.mz`, and so on -- and each bucket is packed greedily in
      program order.

      Cost model: the vectorization factor VF, i.e. the number of elements in one operation, is
      made as large as legality allows. Larger VF means fewer instructions, and the QV encoding
      charges nothing for the width beyond the `vl` it already carries. What this deliberately
      ignores is the `vsetvli` reconfiguration a change of VF (or SEW) costs between two
      instructions, which a uniform-VF policy would trade instruction count for.
      TODO: Weigh reconfiguration against instruction count once there are numbers to weigh with.

      Legality: qubit indices travel as `i8`, so `VF <= VLEN/8 * EMUL` with `EMUL` the smallest
      power of two in `{1,2,4,8}` that fits -- which is exactly the widest register group the QV
      instructions address, `hisepq::Hardware::maxQubits()`. The machine is described by the
      module's `hisepq.target` attribute, and `max-vf` caps it further (never above it), which
      is what lets a test exercise the split without hundreds of gates.

      Merging moves operations, which their `MemRead`/`MemWrite` effects nominally forbid. Those
      effects are a conservative backstop for passes that do not know what a qubit is; here the
      layering establishes that the operations being reordered touch disjoint qubits, and gates on
      disjoint qubits commute.

      A group is cut short when the next operation would exceed VF, would repeat a qubit the group
      already names (which well-formed value-semantics IR cannot do, so this only guards against
      malformed input -- notably `hisepq.pair`, where controls and targets must not overlap
      across the whole group), or when its operands cannot be made available where the merged
      operation goes.

      Operations never merge across blocks or region boundaries.

      Packing takes a qubit vector apart element by element and puts it back together, so the pass
      finishes by running the `vector` canonicalization patterns over the module. Where a merged
      group reads a whole predecessor result back in order that restores the direct operand -- one
      operation threading into the next, with no glue in between -- and one-element vectors come
      out as `vector.broadcast` rather than `vector.from_elements`. Nothing depends on the cleanup
      running: `hisepq::getQubitElement` sees through either form.
  }];

  let options = [
    Option<"maxVF", "max-vf", "unsigned", /*default=*/"0",
           "Cap on the number of elements per operation; 0 derives it from 'hisepq.target'.">
  ];

  let dependentDialects = [
    "mlir::vector::VectorDialect",
    "qcc::hisepq::HiSEPQDialect"
  ];
}

#endif // INCLUDE_QCC_DIALECT_HISEPQ_TRANSFORMS_PASSES_TD_
