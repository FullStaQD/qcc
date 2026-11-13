// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_MAGIC_TRANSFORMS_PASSES_TD_
#define INCLUDE_QCC_DIALECT_MAGIC_TRANSFORMS_PASSES_TD_

include "mlir/Pass/PassBase.td"

def MagicLayer : Pass<"magic-layer", "mlir::func::FuncOp"> {
  let summary = "Schedules the gates into alternating SQ and ZZ layers.";

  let description = [{
      A scheduler for the gates the conversion into `magic` emits: `zxz`, `rz`, `active_zz` and `inter_trap_zz` (rejects
      other ops). It runs before shuttles, swaps and recodes exist, so every ion is active and stays in the trap.

      The gates are replaced by a sequence of *layers*, emitted right behind `magic.init`:

      - an SQ (single-qubit) layer: one `zxz` per trap over all ions that have a rotation ready, or
      - a ZZ layer: one `active_zz` per trap and one `inter_trap_zz` per coupling across traps,

      strictly alternating, followed by at most one residual `rz` per trap (Z rotations that never met a `zxz`) and then
      the `mzd` ops in their original order. All other ops after `magic.init` (e.g. `aux.record_int`) come after the
      measurements, in their original order.

      The schedule is greedy and commutation-aware for the diagonal gates (`rz`, `active_zz`, `inter_trap_zz`). ZZ
      couplings are moved to the earliest layer possible (and merged).

      Example (three ions in one trap):

      ```mlir
      %c0 = magic.init : !c
      %c1 = magic.zxz %c0 ions [0] {z1 = [0.5], x = [0.5], z2 = [0.5]} : !c
      %c2 = magic.zxz %c1 ions [1] {z1 = [0.5], x = [0.5], z2 = [0.5]} : !c
      %c3 = magic.active_zz %c2 {angles = dense<[[0.0, 0.25, 0.0], [0.25, 0.0, 0.25], [0.0, 0.25, 0.0]]>
                                     : tensor<3x3xf64>} : !c
      %c4 = magic.rz %c3 ions [0, 1, 2] {angles = [0.25, 0.25, 0.25]} : !c
      %c5 = magic.zxz %c4 ions [1] {z1 = [0.5], x = [0.5], z2 = [0.5]} : !c
      ```

      turns into

      ```mlir
      %c0 = magic.init : !c
      // SQ layer; the rz of ion 0 is folded back into its zxz (z2 = 0.5 + 0.25).
      %c1 = magic.zxz %c0 ions [0, 1] {z1 = [0.5, 0.5], x = [0.5, 0.5], z2 = [0.75, 0.5]} : !c
      // ZZ layer.
      %c2 = magic.active_zz %c1 {angles = dense<[[0.0, 0.25, 0.0], [0.25, 0.0, 0.25], [0.0, 0.25, 0.0]]>
                                     : tensor<3x3xf64>} : !c
      // SQ layer; the rz of ion 1 is folded into the next zxz (z1 = 0.5 + 0.25).
      %c3 = magic.zxz %c2 ions [1] {z1 = [0.75], x = [0.5], z2 = [0.5]} : !c
      // Ion 2 meets no zxz, so its rz stays: a residual rz behind the layers.
      %c4 = magic.rz %c3 ions [2] {angles = [0.25]} : !c
      ```
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

def MagicShuttleInterTrapZZ : Pass<"magic-shuttle-inter-trap-zz", "mlir::func::FuncOp"> {
  let summary = "Lowers `magic.inter_trap_zz` to shuttles and `active_zz`.";

  let description = [{
      Consider an `inter_trap_zz` between ion `i` of chain `A` (at position `p`) and ion `j` of chain `B`. There are two
      ways to bring the pair together. Both are described as moving towards `B`; each also exists mirrored, moving `j`
      towards `A`:

      - Shuttle: shuttle the `p + 1` front ions of `A` to `B`, apply `active_zz` with the pair as the only nonzero
        entry, shuttle back. Needs `p + 1` free slots in `B`.
      - Swap and shuttle: `swap` `i` with the front ion `f` of `A` (skipped if `p = 0`), shuttle `f` alone,
        `active_zz` on the pair `(f, j)`, shuttle back, `swap` back. Needs one free slot in `B`.

      The pass uses the shuttle variant that moves fewer ions among those that fit. If that is not possible (e.g. too
      little capacity) it uses the swap-and-shuttle variant towards a trap with a free slot. It fails if both traps
      are full.

      An inactive ion of the `active_zz` pair is recoded before the shuttles and back after them.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

def MagicCompileSwap : Pass<"magic-compile-swap", "mlir::func::FuncOp"> {
  let summary = "Decomposes `magic.swap` to three `active_zz` with single-ion gates in between.";

  let description = [{
      `swap(a, b)` becomes three CNOTs which are then further decomposed into `active_zz` and single qubit gates. If
      some of the two participating ions are not already active a recode sandwich is applied to the whole decomposition
      in order to enable the `active_zz` ops.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

def MagicCompileActiveZZTrivially : Pass<"magic-compile-active-zz-trivially", "mlir::func::FuncOp"> {
  let summary = "Lowers every `magic.active_zz` pair by pair to recodes and delays.";

  let description = [{
      For every nonzero entry `A_ij` (`i < j`, row-major order) of an `active_zz` synthesize the corresponding RZZ gate
      in a straightforward way:

      1. `recode` to ensure only the two relevant ions are active,
      2. if `A_ij < 0`: Do an X-flip on ion `i` (`sym_zxz(z = 0, x = pi)`)
      3. `delay` for `t = |A_ij| / J_ij` seconds, rounded to the nearest tick of the device's time unit,
      4. Do the X-flip again if it was needed in step 2 and recode back.

      `J` is the device's coupling matrix for the number of ions present in the trap (active and inactive), indexed by
      the chain positions of the pair.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

def MagicFinalizeZXZ : Pass<"magic-finalize-zxz", "mlir::func::FuncOp"> {
  let summary = "Rewrites `magic.zxz` into native `sym_zxz` and pushes the residual Z rotations into the measurement.";

  let description = [{
      Every `zxz(z1, x, z2)` is rewritten as `sym_zxz(z = z1, x)` followed by `rz(z1 + z2)`. Every residual or
      pre-existing `rz` is commuted to the end: through ops which trivially commute with it or through `shuttle` (it
      travels with its ion). When it hits a `zxz` / `sym_zxz` on the same ion the pattern is replaced by something where
      the `rz` comes later so that it can continue its journey towards the end. What arrives at `mzd` is dropped. Angles
      are normalised to (-pi, pi].

      Not unitary-preserving: the Z rotations dropped before the Z-basis measurement change the state, not the
      measurement statistics.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

def MagicMeasureAndRecordGarbage : Pass<"magic-measure-and-record-garbage", "mlir::func::FuncOp"> {
  let summary = "Measures every ion and records every measurement, marking the added records as garbage.";

  let description = [{
      A program may measure and record less than it loads, but the device measures every ion and reports every result.
      This pass completes the program:

      - Every non-empty chain that is not measured gets a `magic.mzd`.
      - Every measurement result that is not recorded gets an `aux.record_int` carrying the unit attribute
        `magic.garbage_result`. These records come after all records of the program, ordered by ion id.

      ```mlir
      aux.record_int %m {magic.garbage_result} : i1
      ```

      Not output-preserving: the program records more bits than before. The added ones are at the end and marked, so
      a consumer of the output can drop them.

      Run it after dead code elimination (`canonicalize`), which removes what does not contribute to a recorded
      result, so that only ions the program really needs cost a garbage bit.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect", "qcc::aux::AuxDialect"];
}

def MagicCompactIonIds : Pass<"magic-compact-ion-ids", "mlir::func::FuncOp"> {
  let summary = "Renumbers the ions to 0..N-1, trap by trap.";

  let description = [{
      Ion ids need not be dense because canonicalization can remove a chain from `magic.init` if it does not contribute
      to the observable behavior of the program. This pass renumbers the ions in the order `magic.init` lists them, i.e.
      trap by trap and front to back, so that a program with `N` ions uses the ids `0..N-1`. It rewrites the chain types
      and the `ions` lists of all ops. The order of the ids is preserved.

      ```mlir
      %b0 = magic.init : !magic.ion_chain<1, [2:1, 5:1]>
      %b1 = magic.rz %b0 ions [5] {angles = [0.5]} : !magic.ion_chain<1, [2:1, 5:1]>
      ```

      becomes

      ```mlir
      %b0 = magic.init : !magic.ion_chain<1, [0:1, 1:1]>
      %b1 = magic.rz %b0 ions [1] {angles = [0.5]} : !magic.ion_chain<1, [0:1, 1:1]>
      ```
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

def MagicPadTiming : Pass<"magic-pad-timing", "mlir::func::FuncOp"> {
  let summary = "Balances the delays of the two traps of every shuttle.";

  let description = [{
      Every trap has its own clock: the `delay` ticks spent on its chain since the program start. A `shuttle` is a sync
      point for its two traps, which must have spent the same time when it happens. Where they have not, the trap that
      is behind gets the padding right before the shuttle. Padding means adding a `magic.delay`, possibly wrapped in a
      recode sandwich to make sure no ions are active during the `magic.delay`.

      Traps that take no part in a shuttle are left alone.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

def MagicVerify : Pass<"magic-verify", "mlir::func::FuncOp"> {
  let summary = "Checks the magic rules that no single op can check.";

  let description = [{
      The op verifiers check what is true of an op in isolation. This pass holds the rest: the whole-program rules
      and the rules that need the device description in `qcc.device` (required if the function holds magic ops). A
      program that passes is ready for export:

      - At most one `magic.init` per function.
      - Every chain holds at most as many ions as its trap's capacity.
      - Only ops with the `Magic_Native` trait remain.
      - At every `shuttle` its two traps have spent the same time: their `delay` ticks since the program start add
        up to the same.
      - Every measurement result is recorded by at most one `aux.record_int` and used nowhere else, and nothing
        else is recorded.
      - The records marked `magic.garbage_result` come last: no record without the mark follows one with it.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

#endif // INCLUDE_QCC_DIALECT_MAGIC_TRANSFORMS_PASSES_TD_
