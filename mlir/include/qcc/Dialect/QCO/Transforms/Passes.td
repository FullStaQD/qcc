// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCO_TRANSFORMS_PASSES_TD_
#define INCLUDE_QCC_DIALECT_QCO_TRANSFORMS_PASSES_TD_

include "mlir/Pass/PassBase.td"

def QCOAssignStaticQubits : Pass<"qco-assign-static-qubits", "mlir::ModuleOp"> {
  let summary = "Replaces dynamic `qco.alloc` with statically indexed qubits.";

  let description = [{
      Replaces every `qco.alloc` with a `qco.static` carrying the next free
      index, so that a QCO program written against dynamic allocation can enter
      a target pipeline that models qubits as a fixed register file.

      Indices are handed out module-wide in walk order, starting at zero, and
      are never reused: a qubit whose lifetime has ended (via `qco.sink`) does
      not free its index. That is sound but not tight; a target that needs the
      minimal register file wants a liveness-based allocator instead, which is
      a separate pass because it needs the target's qubit count to be worth
      running.

      The pass is the QCO counterpart of `convert-memref-to-static-qubits` on
      the JASP path: both exist because `qc.alloc` is illegal in the QIR
      lowering, which only understands `qc.static`.

      Example:

      ```mlir
      %q0 = qco.alloc : !qco.qubit
      %q1 = qco.alloc : !qco.qubit
      ```

      becomes:

      ```mlir
      %q0 = qco.static 0 : !qco.qubit
      %q1 = qco.static 1 : !qco.qubit
      ```
  }];

  let dependentDialects = ["mlir::qco::QCODialect"];
}

#endif // INCLUDE_QCC_DIALECT_QCO_TRANSFORMS_PASSES_TD_
