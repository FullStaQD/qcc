// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_MAGIC_IR_MAGICDIALECT_TD_
#define INCLUDE_QCC_DIALECT_MAGIC_IR_MAGICDIALECT_TD_

include "mlir/IR/DialectBase.td"
include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// Magic dialect
//===----------------------------------------------------------------------===//

def MagicDialect : Dialect {
    let summary = "Programs for the MAGIC architecture: ion chains in traps coupled by a permanent ZZ interaction.";
    let description = [{
        The MAGIC (Magnetic Gradient Induced Coupling) architecture consists of ion traps ("chains"), each holding a
        line of ions. The only two-qubit interaction is a permanent ZZ coupling that acts between all *active* ions of
        one trap while the trap waits (`magic.delay`). Everything else is single-ion rotations, toggling ions between
        active and inactive (`magic.recode`), moving ions between traps (`magic.shuttle`) and a final destructive
        measurement (`magic.mzd`). The device data (occupancies, coupling strengths, time unit) lives in the module
        attribute `qcc.device` (`#qcc.magic_device`).

        **Chains as values.** The dialect has value semantics: every op consumes its chain operands and produces new
        chain values. The type `!magic.ion_chain<trap, [ion:active, ...]>` records the trap id and, front to back, the
        ions in the trap together with their activation. Chain values are *affine*: each chain value is used at most
        once (a fork is a verifier error; an unused chain value is legal and removed by dead-code elimination).
        `magic.init` is the sole source of chain values: a chain must never reach an op as a block argument, so the
        affine rule is checked on the results and covers forks through consumers outside the dialect too.

        The dialect also has no control flow: every op sits in a single-block region. That is what the timing model
        (one straight line of sync points) and the type-level chain tracking assume.

        **Ions vs positions.** Ions carry an id that never changes; `ions [...]` attributes on ops always refer to
        ids, never to positions. The position of an ion in its chain (front = 0) follows from the chain type and
        changes only through shuttling. Activation only matters for the global operations `active_zz` and `delay`;
        single-ion gates act on active and inactive ions alike.

        FIXME: shorten most stuff below. Elaborate on sync points.

        **Conventions.** Angles are `f64` radians.
        - `zxz(z1, x, z2)` is `Rz(z2)·Rx(x)·Rz(z1)`, i.e. `z1` is applied first. The native `sym_zxz(z, x)` is
          `Rz(-z)·Rx(x)·Rz(z)`. Any `zxz` equals `rz(z1 + z2)` applied after `sym_zxz(z1, x)`.
        - `active_zz` with matrix `A` is `exp(-i/4 Σ_{i≠j} A_ij Z_i Z_j)` over the active ions in position order, `A`
          symmetric with zero diagonal, so that `rzz(θ) = exp(-i θ/2 Z⊗Z)` on ions `(i, j)` is `A_ij = A_ji = θ`.
          `inter_trap_zz {angle = θ}` means `rzz(θ)` between two ions in different traps.
        - `delay {ticks}` waits for `ticks` times the device's time unit while the coupling acts.

        **Native vs intermediate ops.** Native ops (the only ones allowed at export): `init`, `sym_zxz`, `rz`,
        `delay`, `recode`, `shuttle`, `mzd`. Intermediate ops, rejected by the final verifier and the exporter:
        `zxz`, `active_zz`, `inter_trap_zz`, `swap`. Every native op except `shuttle` touches exactly one chain.

        Device rules that need the device description (occupancies against capacities, timing balance between sync
        points) are not checked by the op verifiers but by a dedicated verification pass.

        Example:
        ```mlir
        !t0 = !magic.ion_chain<0, [0:1, 1:1]>
        %a0 = magic.init : !t0
        %a1 = magic.sym_zxz %a0 ions [0] {z = [1.5708], x = [1.5708]} : !t0
        %a2 = magic.delay %a1 {ticks = 2491} : !t0
        %m0, %m1 = magic.mzd %a2 : !t0 -> i1, i1
        ```
    }];

    let name = "magic";
    let cppNamespace = "::qcc::magic";

    let useDefaultTypePrinterParser = 1;
    let useDefaultAttributePrinterParser = 0; // set to 1 once we define attributes of our own.

    let extraClassDeclaration = [{
        /// Registers the dialect's types (implemented next to the type definitions).
        void registerTypes();
    }];
}

#endif // INCLUDE_QCC_DIALECT_MAGIC_IR_MAGICDIALECT_TD_
