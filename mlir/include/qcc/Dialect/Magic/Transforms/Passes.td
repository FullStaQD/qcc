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
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

#endif // INCLUDE_QCC_DIALECT_MAGIC_TRANSFORMS_PASSES_TD_
