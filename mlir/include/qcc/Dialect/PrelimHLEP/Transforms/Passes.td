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

def PrelimHLEPLinToGates : Pass<"prelim-hlep-lin-to-gates", "mlir::ModuleOp"> {
  let summary = "Lowers `prelimhlep.lin` ops to `hlepgate` gates by peeling gates out of them.";

  let description = [{
      Rewrites every `prelimhlep.lin` op into `hlepgate` ops by successively
      peeling gates off its boundary. Each peel is the composition theorem
      read backwards: a
      gate is emitted before (or after) the op, and the body is composed with
      the gate's inverse, so the remaining `lin` op together with the gate
      denotes the original one. The op is erased once its body is the
      identity.

      Bodies are interpreted symbolically over the delinearized input bits
      (constants, zero-extension, truncation, constant shifts, and bitwise
      or/xor/and that never combine two input bits), plus `scf.if` ops in
      one of three forms: a conditional phase (`prelimhlep.scale` by a
      constant), a basis-conditional constant (the Hadamard family), or a
      controlled sub-circuit (a then-branch of gates applied to captured
      linear values, passed through in the else-branch). Ops are processed
      innermost first, so nested bodies have become gates by the time the
      enclosing body is examined.

      The peels run in a fixed order: registers are split into qubits,
      classical `carrying` results are measured, conditionals become
      (controlled) gates, and the remaining bit-level wiring becomes
      allocations, `x` gates, and forwarded qubits. Measured qubits the body
      no longer uses are sunk.

      Anything left over (arithmetic mixing input bits, discarding a qubit
      without measuring it, measurements under a condition, ...) is reported
      as an error; general reversible-circuit synthesis is out of scope.
  }];

  let dependentDialects = ["mlir::arith::ArithDialect", "qcc::hlepgate::HLEPGateDialect",
                           "qcc::prelimhlep::PrelimHLEPDialect"];
}

#endif // INCLUDE_QCC_DIALECT_PRELIMHLEP_TRANSFORMS_PASSES_TD_
