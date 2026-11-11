// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCIRC_TRANSFORMS_PASSES_TD_
#define INCLUDE_QCC_DIALECT_QCIRC_TRANSFORMS_PASSES_TD_

include "mlir/Pass/PassBase.td"

def QCircToRZZ : Pass<"qcirc-to-rzz", "mlir::func::FuncOp"> {
  let summary = "Decomposes every `qcirc.pair` gate into `rzz` and single-qubit gates.";

  let description = [{
      Decomposition happens up to global phase. A constant angle is scaled at compile time, any other one at runtime
      (`arith.mulf`).

      Example:

      ```mlir
      %c1, %t1 = qcirc.pair cz %c0, %t0 : !qcc.qubit
      ```

      turns into

      ```mlir
      %pi_2 = arith.constant 1.5707963267948966 : f64
      %c1, %t1 = qcirc.pair rzz(%pi_2) %c0, %t0 : f64, !qcc.qubit
      %mpi_2 = arith.constant -1.5707963267948966 : f64
      %c2 = qcirc.single rz(%mpi_2) %c1 : f64, !qcc.qubit
      %t2 = qcirc.single rz(%mpi_2) %t1 : f64, !qcc.qubit
      ```
  }];

  let dependentDialects = ["mlir::arith::ArithDialect"];
}

def QCircToUZXZ : Pass<"qcirc-to-u-zxz", "mlir::func::FuncOp"> {
  let summary = "Rewrites every `qcirc.single` gate into `u_zxz` or `rz`.";

  let description = [{
      Rewrites every single-qubit gate kind into the general rotation `u_zxz(z1, x, z2) = Rz(z2) * Rx(x) * Rz(z1)`, up
      to a global phase. Diagonal gates (`z`, `s`, `sdg`, `t`, `tdg`) become `rz` instead, and `rz` stays `rz`: a
      scheduler must be able to see that they commute with `rzz`.

      Example:

      ```mlir
      %q1 = qcirc.single h %q0 : !qcc.qubit
      ```

      turns into

      ```mlir
      %pi_2 = arith.constant 1.5707963267948966 : f64
      %q1 = qcirc.single u_zxz(%pi_2, %pi_2, %pi_2) %q0 : f64, !qcc.qubit
      ```
  }];

  let dependentDialects = ["mlir::arith::ArithDialect"];
}

def QCircFuseZXZ : Pass<"qcirc-fuse-zxz", "mlir::func::FuncOp"> {
  let summary = "Fuses adjacent `u_zxz` / `rz` gates on the same qubit into one.";

  let description = [{
      Two `qcirc.single` gates of kind `u_zxz` or `rz` where the second consumes the qubit the first produces, both
      with constant angles, are replaced by one gate (up to a global phase). Two `rz` fuse into one `rz` by adding
      their angles; every other combination yields a `u_zxz`.

      Example:

      ```mlir
      %q1 = qcirc.single u_zxz(%z1, %x, %z2) %q0 : f64, !qcc.qubit
      %q2 = qcirc.single rz(%t) %q1 : f64, !qcc.qubit
      ```

      turns into

      ```mlir
      %q2 = qcirc.single u_zxz(%z1, %x, %z2_plus_t) %q0 : f64, !qcc.qubit
      ```
  }];

  let dependentDialects = ["mlir::arith::ArithDialect"];
}

#endif // INCLUDE_QCC_DIALECT_QCIRC_TRANSFORMS_PASSES_TD_
