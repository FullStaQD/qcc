// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def MojoResidueToStd : Pass<"mojo-residue-to-std", "mlir::ModuleOp"> {
  let summary = "Translate elaborated Mojo IR into the qcc kernel vocabulary.";

  let description = [{
      Translates the output of `kgen -elaborate -S -mlir-print-op-generic`
      into the dialects the PrelimHLEP pipeline consumes: `func`, `arith`,
      `scf` and `prelimhlep`.

      The input is expected to have been parsed with unregistered dialects
      allowed and with parse-time verification disabled, because the Mojo
      compiler emits `kgen`, `pop` and `hlcf` ops that qcc does not know and
      because a Mojo module is not a well-formed PrelimHLEP program until
      this pass has run. The `prelimhlep` ops themselves arrive fully
      formed: the Mojo fork registers the dialect from this repository's own
      TableGen, so it writes their properties itself.

      The translation is *total on a closed table and loud everywhere
      else*: every op and type that is not in the table below fails the
      pass with a diagnostic at the op's (Mojo source) location. Growing
      the table is a design decision, never an accident.

      | Mojo residue | qcc |
      | --- | --- |
      | `kgen.func` / `kgen.call` / `kgen.return` | `func.func` / `func.call` / `func.return` |
      | `hlcf.if` / `hlcf.yield` | `scf.if` / `scf.yield` |
      | `pop.{add,sub,mul,div,rem,shl,shr}` | `arith.*` (signedness from the dtype) |
      | `pop.simd.{and,or,xor}` | `arith.{andi,ori,xori}` |
      | `pop.cmp` | `arith.cmpi` (predicate signedness from the dtype) |
      | `pop.select` | `arith.select` |
      | `pop.cast` | `arith.{extui,extsi,trunci}` |
      | `pop.cast_to_builtin` / `pop.cast_from_builtin` | identity |
      | `kgen.param.constant` of an integer | `arith.constant` |
      | `kgen.struct.create` / `kgen.struct.extract` | taken apart into the values the fields hold |
      | `prelimhlep.*` | itself |
      | `!kgen.scalar<bool|si*|ui*|index|f*>` | `i1` / `i*` / `index` / `f*` |
      | `complex<f64>` and `complex.*` | themselves |
      | `pop.{stack_allocation,load,store}` | rejected: a body's results leave through `output` |

      Mojo has no multiple return, so a function returning several values
      returns one `!kgen.struct`; this pass takes such a value apart into
      the values its leaves translated to, and a `func.func` gets the result
      types that survive. The same happens to a `prelimhlep.lin` with
      several results, which inline MLIR can only give Mojo as one value.

      Functions whose signature mentions a `prelimhlep` type are tagged
      `prelimhlep.halo`; that is PrelimHLEP's own definition of
      quantum-ness, so no decorator is needed on the Mojo side.
  }];

  let dependentDialects = ["mlir::arith::ArithDialect", "mlir::scf::SCFDialect",
                           "mlir::func::FuncDialect",
                           "qcc::prelimhlep::PrelimHLEPDialect"];
}
