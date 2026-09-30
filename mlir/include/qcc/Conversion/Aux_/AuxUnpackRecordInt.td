// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def AuxUnpackRecordInt : Pass<"aux-unpack-record-int"> {
  let summary = "Splits a recorded integer that packs single bits into one record per bit.";

  let description = [{
      Qrisp returns one integer per quantum variable with the measured bits packed into it, bit `k` being qubit `k`.
      This pass replaces such an `aux.record_int` of an `arith.ori` tree whose leaves are
      `arith.shli(arith.extui(%bit), k)` (no shift for `k = 0`), `%bit : i1`, and whose shifts are exactly
      `0 .. n-1`, by one `aux.record_int %bit : i1` per leaf in ascending `k`:

      ```mlir
      %0 = arith.extui %m0 : i1 to i64
      %1 = arith.extui %m1 : i1 to i64
      %2 = arith.shli %1, %c1_i64 : i64
      %3 = arith.ori %0, %2 : i64
      aux.record_int %3 : i64
      ```

      becomes

      ```mlir
      aux.record_int %m0 : i1
      aux.record_int %m1 : i1
      ```

      The arithmetic left without users is erased. Records of any other shape are left alone.
  }];

  let dependentDialects = [
    "mlir::arith::ArithDialect",
    "::qcc::aux::AuxDialect"
  ];
}
