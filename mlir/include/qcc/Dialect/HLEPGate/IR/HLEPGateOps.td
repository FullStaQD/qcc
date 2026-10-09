// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_HLEPGATE_IR_HLEPGATEOPS_TD_
#define INCLUDE_QCC_DIALECT_HLEPGATE_IR_HLEPGATEOPS_TD_

include "qcc/Dialect/HLEPGate/IR/HLEPGateAttrs.td"
include "qcc/Dialect/HLEPGate/IR/HLEPGateDialect.td"
include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPEffects.td"

include "mlir/IR/OpBase.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// Type constraints
//===----------------------------------------------------------------------===//

def HLEPGate_Qubit : Type<CPred<"::qcc::hlepgate::isQubitType($_self)">, "single qubit ('!prelimhlep.lin<i1>')",
                          "::qcc::prelimhlep::LinType"> {
  let builderCall = "::qcc::hlepgate::getQubitType($_builder.getContext())";
}

def HLEPGate_Register : Type<CPred<"::qcc::hlepgate::getRegisterWidth($_self).has_value()">,
                             "qubit register ('!prelimhlep.lin<i<n>>')", "::qcc::prelimhlep::LinType">;

//===----------------------------------------------------------------------===//
// HLEPGate operations
//===----------------------------------------------------------------------===//

class HLEPGateOp<string mnemonic, list<Trait> traits = []> : Op<HLEPGateDialect, mnemonic, traits>;

def AllocOp : HLEPGateOp<"alloc"> {
  let summary = "Allocates a fresh qubit in the |0> state.";
  let description = [{
      Denotes `prelimhlep.lin () -> (!prelimhlep.lin<i1>)` outputting the
      constant `false`.

      Example:
      ```mlir
      %q = hlepgate.alloc
      ```
  }];

  let results = (outs Res<HLEPGate_Qubit, "", [MemAlloc<PrelimHLEP_QuantumStateResource>]>:$result);
  let assemblyFormat = "attr-dict";
}

def SingleOp : HLEPGateOp<"single", [Pure, AttrSizedOperandSegments, InferTypeOpAdaptor]> {
  let summary = "A (multi-)controlled single-qubit gate.";
  let description = [{
      Applies the gate `kind` to `target` if all `controls` are |1>.
      Parametrized kinds (`p`, `rx`, `ry`, `rz`) take one `f64` angle, the
      others none. The results are the controls, in order, followed by the
      target.

      Conventions follow QCO: `p(a) = diag(1, e^{ia})`, `rz(a) =
      exp(-i a Z / 2)`, and so on.

      Example:
      ```mlir
      %t1 = hlepgate.single h %t0
      %t2 = hlepgate.single p(%angle) %t1
      %c0, %c1, %t3 = hlepgate.single x %t2 ctrl(%a, %b)
      ```

      The verifier checks the number of angles against `kind`.
  }];

  let arguments = (ins HLEPGate_GateKindAttr:$kind,
                       Variadic<F64>:$params,
                       Variadic<HLEPGate_Qubit>:$controls,
                       HLEPGate_Qubit:$target);
  let results = (outs Variadic<HLEPGate_Qubit>:$controlsOut,
                      HLEPGate_Qubit:$targetOut);

  let assemblyFormat = [{
      $kind (`(` $params^ `)`)? $target (`ctrl` `(` $controls^ `)`)? attr-dict
  }];

  let extraClassDeclaration = [{
      /// Number of `f64` angles a gate of `kind` takes.
      static unsigned getNumParams(::qcc::hlepgate::GateKind kind);
  }];

  let hasVerifier = 1;
  let hasFolder = 1;
}

def MeasureOp : HLEPGateOp<"measure", [MemoryEffects<[MemRead<PrelimHLEP_WorldResource>,
                                                               MemWrite<PrelimHLEP_WorldResource>]>]> {
  let summary = "Measures a qubit in the computational basis, keeping it.";
  let description = [{
      Denotes `prelimhlep.lin (%b : i1 from %q) -> (!prelimhlep.lin<i1>, i1)
      { prelimhlep.output (%b : i1) carrying (%b : i1) }`: the qubit
      collapses to the basis state of the outcome.

      The outcome is the value of the hidden world index, which the op reads
      and advances: it is not `Pure`, so that two measurements are never
      merged, hoisted out of a loop, or erased.

      Example:
      ```mlir
      %q1, %bit = hlepgate.measure %q0
      ```
  }];

  let arguments = (ins HLEPGate_Qubit:$qubit);
  let results = (outs HLEPGate_Qubit:$qubitOut, I1:$outcome);
  let assemblyFormat = "$qubit attr-dict";
}

def SinkOp : HLEPGateOp<"sink"> {
  let summary = "Discards a measured qubit.";
  let description = [{
      Discards a qubit that has just been measured. Together with the
      measurement, this denotes `prelimhlep.lin (%b : i1 from %q) -> (i1)
      { prelimhlep.output () carrying (%b : i1) }`.

      Discarding an unmeasured qubit is the linearization of the classical
      discard, which is not a physical operation. The verifier therefore
      requires the operand to be the
      qubit result of a `hlepgate.measure`.

      Example:
      ```mlir
      %q1, %bit = hlepgate.measure %q0
      hlepgate.sink %q1
      ```
  }];

  let arguments = (ins Arg<HLEPGate_Qubit, "", [MemFree<PrelimHLEP_QuantumStateResource>]>:$qubit);
  let assemblyFormat = "$qubit attr-dict";
  let hasVerifier = 1;
}

def SplitOp : HLEPGateOp<"split", [Pure, InferTypeOpAdaptor]> {
  let summary = "Splits a qubit register into its qubits.";
  let description = [{
      Pure rewiring: the results are the qubits of `reg`,
      least-significant bit first. Denotes the `prelimhlep.lin` op whose
      output `j` is bit `j` of the input.

      Example:
      ```mlir
      %q:4 = hlepgate.split %reg : !prelimhlep.lin<i4>
      ```
  }];

  let arguments = (ins HLEPGate_Register:$reg);
  let results = (outs Variadic<HLEPGate_Qubit>:$qubits);
  let assemblyFormat = "$reg attr-dict `:` qualified(type($reg))";
  let hasFolder = 1;
}

def JoinOp : HLEPGateOp<"join", [Pure]> {
  let summary = "Joins qubits into a qubit register.";
  let description = [{
      Pure rewiring, the inverse of `hlepgate.split`: qubit `j` becomes bit
      `j` of the register.

      Example:
      ```mlir
      %reg = hlepgate.join %q0, %q1, %q2, %q3 : !prelimhlep.lin<i4>
      ```

      The verifier checks that the register has one bit per qubit.
  }];

  let arguments = (ins Variadic<HLEPGate_Qubit>:$qubits);
  let results = (outs HLEPGate_Register:$reg);
  let assemblyFormat = "$qubits attr-dict `:` qualified(type($reg))";
  let hasVerifier = 1;
  let hasFolder = 1;
}

#endif // INCLUDE_QCC_DIALECT_HLEPGATE_IR_HLEPGATEOPS_TD_
