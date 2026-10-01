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

def MagicShuttleInterTrapZZ : Pass<"magic-shuttle-inter-trap-zz", "mlir::ModuleOp"> {
  let summary = "Lowers `magic.inter_trap_zz` to shuttles around an `active_zz` in one trap.";

  let description = [{
      Every `inter_trap_zz` between ion `i` of chain `A` (at position `p`) and ion `j` of chain `B` (at position `q`)
      becomes a local sequence that restores the placement, so the result types equal the operand types:

      - Greedy: shuttle the `p + 1` front ions of `A` to `B` (they arrive reversed, `i` in front), apply
        `active_zz` with the pair as the only nonzero entry, shuttle them back. Needs `p + 1` free slots in `B`. The
        mirror image moves `j` to `A`; the cheaper variant that fits is used.
      - Fallback, when neither fits: `swap` `i` with the front ion `f` of `A` (skipped if `p = 0`), shuttle `f`
        alone, `active_zz` on the pair `(f, j)`, shuttle back, `swap` back. Needs one free slot on either side.

      Both ions must be active. Capacities come from the device in `qcc.device`; a pass failure is reported if no
      trap has a free slot.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

def MagicCompileSwap : Pass<"magic-compile-swap", "mlir::ModuleOp"> {
  let summary = "Lowers `magic.swap` to three `active_zz` with single-ion gates in between.";

  let description = [{
      `swap(a, b)` becomes three CNOTs `cx(a, b) cx(b, a) cx(a, b)`, each as `h` on the target, `cz`, `h` on the
      target, where `cz = active_zz(pi/2 on the pair)` followed by `rz(-pi/2)` on both ions and `h` is
      `zxz(pi/2, pi/2, pi/2)`. Exact up to a global phase. Both ions must be active.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

def MagicCompileActiveZZTrivially : Pass<"magic-compile-active-zz-trivially", "mlir::ModuleOp"> {
  let summary = "Lowers every `magic.active_zz` pair by pair to recodes and delays.";

  let description = [{
      For every nonzero entry `A_ij` (`i < j`, row-major order) of an `active_zz` synthesize the corresponding RZZ gate
      in a straightforward way:

      1. `recode` to ensure only the two relevant ions are active,
      2. if `A_ij` and `J_ij` differ in sign: Do an X-flip on ion `i` (`sym_zxz(z = 0, x = pi)`)
      3. `delay` for `t = |A_ij| / |J_ij|` seconds, rounded to the nearest tick of the device's time unit,
      4. Do the X-flip again if it was needed in step 2 and recode back.

      `J` is the device's coupling matrix for the number of ions present in the trap (active and inactive), indexed by
      the chain positions of the pair.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

def MagicFinalizeZXZ : Pass<"magic-finalize-zxz", "mlir::ModuleOp"> {
  let summary = "Rewrites `magic.zxz` into native `sym_zxz` and pushes the residual Z rotations into the measurement.";

  let description = [{
      `zxz(z1, x, z2) = Rz(z2) Rx(x) Rz(z1)` equals `sym_zxz(z = z1, x)` followed by `rz(z1 + z2)`. Every `zxz` is
      rewritten that way, and every residual or pre-existing `rz` is commuted to the right: through `delay`,
      `recode`, `active_zz` and `inter_trap_zz` (all diagonal), through `shuttle` (it travels with its ion), and into
      the following `zxz` / `sym_zxz` on the same ion (`sym_zxz(z, x)` after `rz(r)` is `rz(r)` after
      `sym_zxz(z + r, x)`). What arrives at `mzd` is dropped. Angles are normalised to (-pi, pi].

      Not unitary-preserving: the Z rotations dropped before the Z-basis measurement change the state, not the
      measurement statistics.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

def MagicPadTiming : Pass<"magic-pad-timing", "mlir::ModuleOp"> {
  let summary = "Balances the delays of all traps between sync points.";

  let description = [{
      Sync points are the program start, every `shuttle` and the final measurement. Between two of them all traps must
      spend the same time. For every segment the pass sums the `delay` ticks per trap; each trap with ions and a
      smaller sum than the maximum gets, at the end of its segment, a `recode` of all its active ions to inactive (so
      the coupling does nothing), one `delay` with the difference, and the `recode` back.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

def MagicVerify : Pass<"magic-verify", "mlir::ModuleOp"> {
  let summary = "Checks the magic rules that no single op can check.";

  let description = [{
      The op verifiers check what is true of an op in isolation. This pass holds the rest: the whole-program rules
      and the rules that need the device description in `qcc.device` (required if the module holds magic ops). A
      program that passes is ready for export:

      - At most one `magic.init` per function; its chains match the device: the initial occupancies, ion ids
        assigned trap by trap, all active.
      - Every chain holds at most as many ions as its trap's capacity.
      - Only ops with the `Magic_Native` trait remain.
      - Between two sync points (program start, every `shuttle`, the final measurement) the `delay` ticks of all
        traps with ions add up to the same time.
      - Every non-empty chain ends in `magic.mzd`, every ion is measured exactly once, every measurement result is
        recorded by exactly one `aux.record_int`, and nothing else is recorded.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

#endif // INCLUDE_QCC_DIALECT_MAGIC_TRANSFORMS_PASSES_TD_
