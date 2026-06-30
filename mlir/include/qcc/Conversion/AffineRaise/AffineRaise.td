// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

//===----------------------------------------------------------------------===//
// TmpSCFToAffine
//===----------------------------------------------------------------------===//

def TmpRaiseSCFToAffinePass : Pass<"tmp-raise-scf-to-affine"> {
  let summary = "Raise SCF operations to affine operations (best effort)";
  let description = [{
    TODO: Temporary solution. Ported from https://github.com/llvm/llvm-project/pull/200851.
    Once our dependency includes this, this may be deleted.

    Raising to the affine dialect enables affine analyses and transforms such
    as loop tiling, unrolling, vectorization, and dependence analysis.
    Currently only `scf.for` is handled; loops that cannot be raised are left
    unchanged.

    A `scf.for` is raised when its lower and upper bounds are valid affine
    dimensions (or an `affine.max` / `affine.min` respectively) and its step
    is a valid affine symbol. Two cases are handled:

      - Constant step: raised directly, preserving the step and any
        `affine.min` / `affine.max` bounds as the loop's bounds.
      - Dynamic (symbolic) step: the loop is normalized to unit step and the
        original induction variable is reconstructed in the body. An
        `affine.min` upper bound is supported here; an `affine.max` lower bound
        is not, as it cannot be raised soundly without a constant step.

    Bounds and step of non-`index` type are cast to `index` first if the source
    type allows lossless conversion (otherwise we do not touch the loop). In any
    case we preserve semantics.

    This pass does not modify memory accesses; use `--affine-raise-from-memref`
    to convert `memref.load` / `memref.store`.
  }];
  let dependentDialects = [
    "mlir::affine::AffineDialect",
    "mlir::arith::ArithDialect",
  ];
}


def WhileToFor : Pass<"while-to-for"> {
  let summary = "Convert scf.while loops to scf.for loops using uplift patterns.";

  let description = [{
      Applies the builtin SCF uplift patterns to rewrite eligible `scf.while` loops as
      `scf.for` loops.

      The pass matches roughly on the following pattern:

      ```
      %i_out, ... = scf.while (%i = %lb, ...) : (i64, ...) -> (i64, ...) {
        %done = arith.cmpi slt, %i, %ub : i64
        scf.condition(%done) %i, ... : i64, ...
      } do {
      ^bb0(%i: i64, ...):
        ...
        %next_i = arith.addi %i, %step : i64
        scf.yield %next_i, ... : i64, ...
      }
      ```

      In preparation, candidate `arith.cmpi` operations are rewritten from `sle` to `slt`, since
      upper bounds of `scf.for` are exclusive. This change may cause undefined behavior due to overflow.
   }];

  let dependentDialects = [
    "mlir::scf::SCFDialect"
  ];
}
