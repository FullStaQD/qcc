// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def AuxOutputRecording : Pass<"convert-return-to-output-recording"> {
  let summary = "Replaces return values of entry point function by record ops.";
  let description = [{
      This pass replaces integer returns of the entry point function with `aux.record_int` and
      changes the return to void. We assume that the entry point function has exactly one block and that all return
      operations in that block return integer values.

      For example, if we have an entry point function like this:

      ```mlir
      %result = some_operation() : () -> i64
      return %result : i64
      ```

      After applying this pass, it will be transformed to:

      ```mlir
      %result = some_operation() : () -> i64
      aux.record_int %result : i64
      return
      ```
    This pass is a workaround to enable output recording for integer values, as our principal
    dialects do not have a direct way to represent the necessary functionality for recording outputs.
    TODO: In the future we want to extend the output recording to more complex types such as tuples
    and arrays.
   }];
    let dependentDialects = [
    "mlir::func::FuncDialect",
    "::qcc::aux::AuxDialect"
    ];
}
