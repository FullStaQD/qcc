// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def PrelimHLEPToQCO : Pass<"prelim-hlep-to-qco", "mlir::ModuleOp"> {
  let summary = "Convert the PrelimHLEP dialect to the QCO dialect.";

  let description = [{
      Lowers haloed PrelimHLEP functions to the MQT-core QCO
      (value-semantics) dialect.

      Types are converted 1:N: `!prelimhlep.lin<i<n>>` (and its X-/Y-basis
      variants `!prelimhlep.lin<!prelimhlep.x<n>>`,
      `!prelimhlep.lin<!prelimhlep.y<n>>`) become `n` individual
      `!qco.qubit` values, least-significant bit first. A `!qco.qubit`
      always holds the physical state; the X-/Y-basis element types are
      purely static tags, so `prelimhlep.base_change` lowers to nothing and
      basis rotations are only emitted where states are created.
      `!prelimhlep.unit` values are erased.

      `prelimhlep.lin` ops must be in normal form, i.e. tagged with one of
      the shapes `--prelim-hlep-normalize-lin` produces (`alloc`, `split`,
      `join`, `x`, `measure`, `measure_drop`, `hadamard`, `phase`, `ctrl`;
      see "Normal form of `lin` ops" in mlir/docs/Dialects/PrelimHLEP.md).
      Each shape maps onto one QCO op (allocation, rewiring, `x`,
      `measure` (+ `sink`), `h` (+ `s`), `z`/`p`, `ctrl`); untagged ops are
      reported as errors.

      The pass expects calls between haloed functions to have been inlined
      beforehand (e.g. via `--inline`). `prelimhlep.exp` is only supported
      for single-term Hamiltonians whose Pauli product maps onto a QCO
      rotation gate.
  }];

  let dependentDialects = ["mlir::qco::QCODialect", "mlir::arith::ArithDialect",
                           "mlir::scf::SCFDialect", "mlir::func::FuncDialect"];
}
