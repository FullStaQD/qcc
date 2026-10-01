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
      Expects the output of `qvec-layer` in every `func.func` with `qvec` operations: `qco.static` qubits,
      alternating `single u_zxz` layers and `global zz` blocks with constant angles, optionally one trailing
      `single rz` layer, then `mz`, and `aux.record_int` of the measured bits.

      Placement is the identity: static qubit `i` is ion `i`; trap 0 holds the first ions up to its initial
      occupancy, the next trap the following ones, and so on. One `magic.init` creates all chains. Then:

      - `single u_zxz` / `single rz` become one `magic.zxz` / `magic.rz` per trap with lanes in the layer.
      - `global zz` with matrix `A` becomes one `magic.active_zz` per trap for the block of `A` within the trap, and
        one `magic.inter_trap_zz` per nonzero entry of `A` between two traps.
      - The first `mz` measures every chain with `magic.mzd`; the recorded bits are the `mzd` results.

      Rejected with a diagnostic: more qubits than ions, dynamic allocation, non-constant or asymmetric angles, a
      layer order other than the above, gates after a measurement, an ion that is not measured exactly once, a
      measurement that is not recorded exactly once, and every other operation. Afterwards a function holds only
      `magic` ops, `aux.record_int`, `arith.constant` and its terminator.
  }];

  let dependentDialects = [
    "qcc::magic::MagicDialect"
  ];
}
