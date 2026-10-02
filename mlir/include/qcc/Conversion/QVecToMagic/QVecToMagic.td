// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def ConvertQVecToMagic : Pass<"convert-qvec-to-magic", "mlir::func::FuncOp"> {
  let summary = "Converts layered QVec programs to magic IR for the device in `qcc.device`.";

  let description = [{
      Expects the output of `qvec-layer`: static qubits, `single u_zxz` layers alternating with `global zz` blocks
      (constant angles), and a final measurement of every qubit whose bits are recorded. Anything else is rejected.

      Static qubit `i` becomes ion `i`. If all ions fit into trap 0 they go there. Otherwise the traps are filled one
      by one, leaving one slot free per trap for shuttling.

      - `single u_zxz` / `single rz` become one `magic.zxz` / `magic.rz` per trap.
      - `global zz` becomes one `magic.active_zz` per trap and one `magic.inter_trap_zz` per coupling across traps.
      - `mz` becomes one `magic.mzd` per trap.
  }];

  let dependentDialects = [
    "qcc::magic::MagicDialect"
  ];
}
