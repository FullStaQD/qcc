// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_PRELIMHLEP_TRANSFORMS_PASSES_TD_
#define INCLUDE_QCC_DIALECT_PRELIMHLEP_TRANSFORMS_PASSES_TD_

include "mlir/Pass/PassBase.td"

def PrelimHLEPNormalizeLin : Pass<"prelim-hlep-normalize-lin", "mlir::ModuleOp"> {
  let summary = "Decomposes `prelimhlep.lin` ops into chains of tagged normal-form shapes.";

  let description = [{
      Rewrites every untagged `prelimhlep.lin` op into a chain of `lin` ops
      tagged with one of the normal-form shapes (`alloc`, `split`, `join`,
      `x`, `measure`, `measure_drop`, `hadamard`, `phase`, `ctrl`; see
      "Normal form of `lin` ops" in mlir/docs/Dialects/PrelimHLEP.md).
      Each shape corresponds directly to one gate, measurement, or
      register rewiring, so a backend conversion only has to dispatch on
      the tag.

      The decomposition is semantics-preserving within PrelimHLEP: a `lin`
      body is a classical function applied linearly, and composing `lin`
      ops composes their functions. Bodies are interpreted symbolically
      over the delinearized input bits (constants, zero-extension,
      truncation, constant shifts, and bitwise or/xor/and that never
      combine two input bits), plus at most one `scf.if` in one of three
      structural forms: a conditional phase (`prelimhlep.scale` by a
      constant), a basis-conditional constant (the Hadamard family), or a
      controlled sub-circuit (a then-branch of already-normalized `lin`
      ops applied to captured linear values, passed through in the
      else-branch). Ops are processed innermost first, so nested bodies
      are in normal form by the time the enclosing body is examined.

      Bodies outside this fragment (arithmetic mixing input bits,
      discarding a qubit without measuring it, ...) are reported as
      errors; general reversible-circuit synthesis is out of scope.
      Already-tagged ops are left alone, so the pass may be re-run.
  }];

  let dependentDialects = ["mlir::arith::ArithDialect", "mlir::complex::ComplexDialect", "mlir::scf::SCFDialect",
                           "qcc::prelimhlep::PrelimHLEPDialect"];
}

#endif // INCLUDE_QCC_DIALECT_PRELIMHLEP_TRANSFORMS_PASSES_TD_
