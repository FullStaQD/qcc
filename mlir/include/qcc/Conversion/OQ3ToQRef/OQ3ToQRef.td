// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def ConvertOQ3ToQRef : Pass<"convert-oq3-to-qref", "mlir::ModuleOp"> {
  let summary = "Converts an OpenQASM program of the `oq3` dialect to `qref`.";

  let description = [{
      Lowers the program to the reference-semantics `qref` dialect and builtin dialects. The program structure
      (`oq3.version`, includes, pragmas, annotations) is dropped. The entry function keeps its `qcc.entry_point`
      attribute.

      Notable behavior:
      - The unsized `int` and `float` have the target's word size, the width of `index` in the module's data layout
        (`dlti.dl_spec`), e.g. `i32` and `f32` for `#dlti.dl_spec<index = 32>`. Without a data layout this is 64.
      - `qubit` declarations become `qcc.alloc`, a register `!oq3.qreg<n>` a `tensor<nx!qcc.qubit_ref>`.
      - A physical qubit `$n` is `qcc.static_ref [n]`.
      - `!qcc.angle` becomes `f64` radians in [0, 2π). Every operation that produces an angle reduces its
        result modulo 2π, as OpenQASM's angle type does. This matters for gates that are not 2π-periodic up to a
        global phase, such as `crz`. TODO: This part of the specification is inconsistent, see also https://github.com/openqasm/openqasm/issues/703
      - `qref` does not model a global phase, so `gphase` and `id` are dropped, `p` becomes `rz`, and `U`, `u3`, and `u2` become `u_zyz`.
      - Barriers are dropped.
      - Register operands are broadcast with an `scf.parallel`.

      Example:
      ```mlir
      %q = oq3.qubit_decl "q" : !qcc.qubit_ref
      oq3.gate_call @h [%q : !qcc.qubit_ref]
      %c = oq3.declare "c" : !qcc.ref<!oq3.bit>
      %m = oq3.measure %q : !qcc.qubit_ref -> !oq3.bit
      qcc.ref.store %m, %c : !qcc.ref<!oq3.bit>

      %q = qcc.alloc : !qcc.qubit_ref
      qref.single h %q : !qcc.qubit_ref
      %alloca = memref.alloca() : memref<i1>
      %c = memref.cast %alloca : memref<i1> to memref<i1, strided<[], offset: ?>>
      %m = qref.measure z %q : !qcc.qubit_ref -> i1
      memref.store %m, %c[] : memref<i1, strided<[], offset: ?>>
      ```
   }];

  let dependentDialects = [
    "mlir::arith::ArithDialect",
    "mlir::memref::MemRefDialect",
    "mlir::scf::SCFDialect",
    "mlir::tensor::TensorDialect",
    "qcc::QccDialect",
    "qcc::qref::QRefDialect"
  ];
}
