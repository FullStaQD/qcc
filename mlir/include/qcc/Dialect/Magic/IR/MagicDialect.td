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
        measurement (`magic.mzd`). The device data (occupancies, coupling strengths, time unit) lives in the dialect's
        own `#magic.device` attribute, which the module carries as `qcc.device`.

        **Chains are affine values.** More precisely we impose the following constraints:

        - each chain value is used at most once
        - `magic` ops are only allowed inside single-block function-like ops
        - only `magic` ops are allowed to produce chain values (magic.init` being its only source)

        **Native vs intermediate ops.** The `Magic_Native` trait marks the native instructions of the hardware; the
        others are intermediate and are lowered to native ones before export.

        **Sync points.** The `magic.delay` operation is the only *native* operation which takes a certain amount of
        time. All other *native* operations are instant. Shuttle operations (native) are *sync points*: the traps
        between it shuttles have to have the same amount of time being passed in a valid program. This is checked by a
        dedicated pass.

        Example:
        ```mlir
        // A chain *type* with with ions 3 and 8, both activated.
        !t0 = !magic.ion_chain<0, [3:1, 8:1]>

        // Initialize a trap (chain).
        %a0 = magic.init : !t0
        // A gate on ion 3 (within the given trap).
        %a1 = magic.sym_zxz %a0 ions [3] {z = [1.5708], x = [1.5708]} : !t0
        // Global ZZ interaction via delay.
        %a2 = magic.delay %a1 {ticks = 2491} : !t0
        // Measurement comes last.
        %m0, %m1 = magic.mzd %a2 : !t0 -> i1, i1
        ```
    }];

    let name = "magic";
    let cppNamespace = "::qcc::magic";

    let useDefaultTypePrinterParser = 1;
    let useDefaultAttributePrinterParser = 1;

    let extraClassDeclaration = [{
        /// Registers the dialect's attributes (implemented next to the attribute definitions).
        void registerAttributes();

        /// Registers the dialect's types (implemented next to the type definitions).
        void registerTypes();
    }];
}

#endif // INCLUDE_QCC_DIALECT_MAGIC_IR_MAGICDIALECT_TD_
