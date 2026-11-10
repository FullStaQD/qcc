// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def ConvertQRefToOQ3 : Pass<"convert-qref-to-oq3", "mlir::ModuleOp"> {
  let summary = "Converts a `qref` program to the `oq3` dialect, for export to OpenQASM.";

  let description = [{
      Translates the entry function (`qcc.entry_point`) of the module into an OpenQASM program of the `oq3`
      dialect that `qcc-translate --export-openqasm` can print. The module gets the `oq3.version` attribute of
      qcc's default version.

      The entry function must be a single block of straight-line code. Notable behavior:
      - `qcc.alloc` (a qubit or a static-size array) becomes a `qubit` declaration.
      - `qcc.static_ref` becomes a physical qubit `$n`.
      - `qcc.dealloc` is dropped.

      Example:
      ```mlir
      %q = qcc.alloc : !qcc.qubit_ref
      qref.single h %q : !qcc.qubit_ref
      %m = qref.measure z %q : !qcc.qubit_ref -> i1
      
      oq3.include "stdgates.inc" id 0
      %q = oq3.qubit_decl "q0" : !qcc.qubit_ref
      oq3.gate_call @h [%q : !qcc.qubit_ref]
      %m = oq3.measure %q : !qcc.qubit_ref -> !oq3.bit
      ```
   }];

  let dependentDialects = [
    "qcc::oq3::OQ3Dialect",
    "qcc::QccDialect"
  ];
}
