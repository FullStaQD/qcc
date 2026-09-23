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

def MagicVerify : Pass<"magic-verify", "mlir::ModuleOp"> {
  let summary = "Checks the magic rules that no single op can check.";

  let description = [{
      The op verifiers check what is true of an op in isolation. This pass holds the rest: the whole-program rules
      and the rules that need the device description in `qcc.device`.

      Currently checked:

      - A program creates its chains once: at most one `magic.init` in the module. All traps are created by that one
        op, which is what makes its cross-trap checks (distinct trap ids, distinct ion ids) cover the whole program.

      TODO: the remaining rules of the dialect description belong here as they are implemented: initial occupancies
      and chain contents against the device, ion capacities, timing balance between sync points, and rejecting the
      intermediate ops (`zxz`, `active_zz`, `inter_trap_zz`, `swap`) that must not reach the exporter.
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}

#endif // INCLUDE_QCC_DIALECT_MAGIC_TRANSFORMS_PASSES_TD_
