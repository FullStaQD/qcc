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

      TODO: Parametrised gates (`single rz`, `pair rzz`, ...) and `global` gates are left alone for now: merging
      them means concatenating their angle vectors, respectively forming the direct sum of their matrices.

      Example:

      ```mlir
      // Assuming %v0, %v1, %v2 are known to refer to disjoint sets of qubits.
      %h0 = qvec.single h %v0 : vector<4x!qco.qubit>
      %x1 = qvec.single x %v1 : vector<3x!qco.qubit> // despite obstacle we can still merge the hadamards
      %h2 = qvec.single h %v2 : vector<2x!qco.qubit>
      ```

      turns into

      ```mlir
      // %4 represents the union of %v0 and %v1 in that order.
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

def QVecToRzz : Pass<"qvec-to-rzz", "mlir::ModuleOp"> {
  let summary = "Decomposes every `qvec.pair` gate into `rzz` and single-qubit gates.";

  let description = [{
      Rewrites every two-qubit gate kind into `pair rzz` plus `single` gates, lane-uniformly and up to a global
      phase, so that the only entangling gate left is `rzz`:

      - `cz`      = `rz(-pi/2) (x) rz(-pi/2) * rzz(pi/2)`
      - `cx`      = `h_t * cz * h_t`
      - `cy`      = `s_t * cx * sdg_t`
      - `cp(t)`   = `rz_c(t/2) * rz_t(t/2) * rzz(-t/2)`
      - `iswap`   = `swap * cz * (s (x) s)` with `swap` as three `cx`
      - `rzz`     stays.

      The single-qubit gates come out as `h`, `s`, `sdg` and `rz`; run `qvec-to-u-zxz` afterwards to turn them into
      `u_zxz`. Constant angles stay constant (`arith.constant dense<...>`); an SSA angle of `cp` is scaled with
      `arith.mulf`.

      Example:

      ```mlir
      %c1, %t1 = qvec.pair cz %c0, %t0 : vector<2x!qco.qubit>
      ```

      turns into

      ```mlir
      %pi_2 = arith.constant dense<1.5707963267948966> : vector<2xf64>
      %mpi_2 = arith.constant dense<-1.5707963267948966> : vector<2xf64>
      %c1, %t1 = qvec.pair rzz(%pi_2) %c0, %t0 : vector<2x!qco.qubit>, vector<2xf64>
      %c2 = qvec.single rz(%mpi_2) %c1 : vector<2x!qco.qubit>, vector<2xf64>
      %t2 = qvec.single rz(%mpi_2) %t1 : vector<2x!qco.qubit>, vector<2xf64>
      ```
  }];

  let dependentDialects = [
    "mlir::arith::ArithDialect",
    "qcc::qvec::QVecDialect"
  ];
}

def QVecToUZxz : Pass<"qvec-to-u-zxz", "mlir::ModuleOp"> {
  let summary = "Rewrites every `qvec.single` gate into `u_zxz` or `rz`.";

  let description = [{
      Rewrites every single-qubit gate kind into the general rotation `u_zxz(z1, x, z2) = Rz(z2) * Rx(x) * Rz(z1)`
      with constant angle vectors, up to a global phase. Diagonal gates (`z`, `s`, `sdg`, `t`, `tdg`) become `rz`
      instead, and `rz` stays `rz`: a scheduler must be able to see that they commute with `rzz` / `zz`.

      - `i` = `u_zxz(0, 0, 0)`, `x` = `u_zxz(0, pi, 0)`, `y` = `u_zxz(-pi/2, pi, pi/2)`, `h` = `u_zxz(pi/2, pi/2, pi/2)`
      - `rx(t)` = `u_zxz(0, t, 0)`, `ry(t)` = `u_zxz(-pi/2, t, pi/2)`
      - `z` = `rz(pi)`, `s` = `rz(pi/2)`, `sdg` = `rz(-pi/2)`, `t` = `rz(pi/4)`, `tdg` = `rz(-pi/4)`

      Example:

      ```mlir
      %h = qvec.single h %qs : vector<2x!qco.qubit>
      ```

      turns into

      ```mlir
      %pi_2 = arith.constant dense<1.5707963267948966> : vector<2xf64>
      %h = qvec.single u_zxz(%pi_2, %pi_2, %pi_2) %qs : vector<2x!qco.qubit>, vector<2xf64>
      ```
  }];

  let dependentDialects = [
    "mlir::arith::ArithDialect",
    "qcc::qvec::QVecDialect"
  ];
}

def QVecFuseZxz : Pass<"qvec-fuse-zxz", "mlir::ModuleOp"> {
  let summary = "Fuses adjacent `u_zxz` / `rz` gates on the same qubit vector into one `u_zxz`.";

  let description = [{
      Two `qvec.single` gates of kind `u_zxz` or `rz` where the second consumes exactly the vector the first
      produces, both with constant angles, are replaced by one gate: per lane the two 2x2 unitaries are multiplied and
      the product is decomposed into ZXZ angles again (up to a global phase). Two `rz` fuse into one `rz` by adding
      their angles; every other combination yields a `u_zxz`.

      Example:

      ```mlir
      %a = qvec.single u_zxz(%z1, %x, %z2) %qs : vector<1x!qco.qubit>, vector<1xf64>
      %b = qvec.single rz(%t) %a : vector<1x!qco.qubit>, vector<1xf64>
      ```

      turns into

      ```mlir
      %b = qvec.single u_zxz(%z1, %x, %z2_plus_t) %qs : vector<1x!qco.qubit>, vector<1xf64>
      ```
  }];

  let dependentDialects = [
    "mlir::arith::ArithDialect",
    "qcc::qvec::QVecDialect"
  ];
}

def QVecLayer : Pass<"qvec-layer", "mlir::ModuleOp"> {
  let summary = "Rebuilds straight-line `qvec` functions as alternating `u_zxz` layers and `global zz` blocks.";

  let description = [{
      A scheduler for the gate set `single u_zxz` / `single rz` / `pair rzz` / `global zz` / `mz` (run
      `qvec-to-rzz` and `qvec-to-u-zxz` first) over static qubits (`qco.static`) with constant angles. Every
      `func.func` containing `qvec` operations gets its body rebuilt from scratch as a sequence of *layers*:

      - one wide `single u_zxz` over all qubits that have a rotation ready, or
      - one `global zz` block with a constant symmetric matrix over all qubits it couples,

      strictly alternating, followed by at most one wide `single rz` (diagonal rotations that never met a `u_zxz`),
      then one `mz` per measured vector of the input and finally the classical operations of the input (e.g.
      `aux.record_int`) in their original order. Qubit vectors are rebuilt with `vector.from_elements` /
      `vector.extract` from fresh `qco.static` ops, so the static provenance of every lane is kept.

      The schedule is greedy and commutation-aware: diagonal gates (`rz`, `rzz`, `zz`) commute with each other and
      gates on distinct qubits commute; nothing else does. An `rzz` / `zz` joins the latest block such that only
      diagonal gates touch its qubits between that block and the gate; two couplings of the same pair in one block
      *add* their angles. `rz` gates float over blocks and are folded into the neighbouring `u_zxz`; consecutive
      `u_zxz` on one qubit are fused. The pass is deliberately device-agnostic: layers span all qubits, and since ZZ
      terms commute a block may be split by trap for free further down.

      Rejected with a diagnostic: functions with more than one block or control flow, qubits not traceable to a
      `qco.static`, non-constant angles, gate kinds other than the ones above, and gates on a qubit after its
      measurement.

      Example (a Bell pair after `qvec-to-rzz` and `qvec-to-u-zxz`, sketched):

      ```mlir
      %h = qvec.single u_zxz(...) %q0 : vector<1x!qco.qubit>, vector<1xf64>
      %t = qvec.single u_zxz(...) %q1 : vector<1x!qco.qubit>, vector<1xf64>   // the h of the cx = h cz h
      %a, %b = qvec.pair rzz(%pi_2) %h, %t : vector<1x!qco.qubit>, vector<1xf64>
      %a1 = qvec.single rz(%mpi_2) %a : ...
      %b1 = qvec.single rz(%mpi_2) %b : ...
      %b2 = qvec.single u_zxz(...) %b1 : ...
      ```

      turns into

      ```mlir
      %l0 = qvec.single u_zxz(%z1, %x, %z2) %qs : vector<2x!qco.qubit>, vector<2xf64>   // h on both
      %l1 = qvec.global zz(%A) %l0 : vector<2x!qco.qubit>, vector<2x2xf64>              // A = [[0, pi/2], [pi/2, 0]]
      %l2 = qvec.single u_zxz(%z1', %x', %z2') %l1 : vector<2x!qco.qubit>, vector<2xf64> // rz folded into the h
      ```
  }];

  let dependentDialects = [
    "mlir::arith::ArithDialect",
    "mlir::qco::QCODialect",
    "mlir::vector::VectorDialect",
    "qcc::qvec::QVecDialect"
  ];
}

#endif // INCLUDE_QCC_DIALECT_QVEC_TRANSFORMS_PASSES_TD_
