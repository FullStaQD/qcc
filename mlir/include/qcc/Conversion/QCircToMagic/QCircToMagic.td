// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def ConvertQCircToMagic : Pass<"convert-qcirc-to-magic", "mlir::func::FuncOp"> {
  let summary = "Converts `qcirc` programs to magic IR for the device in `qcc.device`.";

  let description = [{
      Converts gate by gate, in program order. Expects the gates `single u_zxz`, `single rz` and `pair rzz` with
      constant angles and `measure z`. A measured bit is recorded by one `aux.record_int` or left unused. Anything else
      is rejected.

      Static qubit `i` becomes ion `i`. If all ions fit into trap 0 they go there. Otherwise the traps are filled one by
      one, leaving one slot free per trap for shuttling. The resulting IR contains at most the following `magic`
      operations: `init`, `zxz`, `rz`, `active_zz`, `inter_trap_zz`, and `mzd`.

      The magic ops are emitted right behind a `magic.init` at the start of the function, so all other ops (e.g. the
      records) stay where they are. A function without `qcc.static` is left alone.

      Preconditions:
      - Only `qcc.static` and `qcirc` ops use qubits.
      - No gate or second measurement on a qubit after its measurement (`magic` measures destructively).

      Example (one trap, `%theta = 0.5`):

      ```mlir
      %q:3 = qcc.static [0, 1, 2] : !qcc.qubit
      %q0 = qcirc.single rz(%theta) %q#0 : f64, !qcc.qubit
      %q0_1, %bit = qcirc.measure z %q0 : !qcc.qubit -> i1
      aux.record_int %bit : i1
      %q1, %q2 = qcirc.pair rzz(%theta) %q#1, %q#2 : f64, !qcc.qubit
      ```

      becomes

      ```mlir
      %c0 = magic.init : !chain // !magic.ion_chain<0, [0:1, 1:1, 2:1]>
      %c1 = magic.rz %c0 ions [0] {angles = [0.5]} : !chain
      %c2 = magic.active_zz %c1 {angles = dense<[[0.0, 0.0, 0.0], [0.0, 0.0, 0.5], [0.0, 0.5, 0.0]]>
                                     : tensor<3x3xf64>} : !chain
      %bits:3 = magic.mzd %c2 : !chain -> i1, i1, i1
      aux.record_int %bits#0 : i1
      ```
  }];

  let dependentDialects = ["qcc::magic::MagicDialect"];
}
