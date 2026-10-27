// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QREF_IR_QREFOPS_TD_
#define INCLUDE_QCC_DIALECT_QREF_IR_QREFOPS_TD_

include "qcc/Dialect/QRef/IR/QRefDialect.td"
include "qcc/Dialect/Qcc/IR/QccAttrs.td"
include "qcc/Dialect/Qcc/IR/QccInterfaces.td"
include "qcc/Dialect/Qcc/IR/QccTypes.td"

include "mlir/IR/CommonTypeConstraints.td"
include "mlir/IR/OpBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// QRef operations
//===----------------------------------------------------------------------===//

// A qubit operand: the operation acts on the qubit that the reference names, so it reads and writes it.
class QRef_QubitArg<string desc>
    : Arg<Qcc_QubitRefType, desc, [MemRead<Qcc_QubitResource>, MemWrite<Qcc_QubitResource>]>;

class QRef_Op<string mnemonic, list<Trait> traits = []> : Op<QRef_Dialect, mnemonic, traits>;

def QRef_SingleOp : QRef_Op<"single"> {
  let summary = "single-qubit gate";
  let description = [{
        Applies a single-qubit gate to `qubit`.

        A parametrised gate takes its angles (radians) as operands. How many it takes is fixed per gate kind (see the
        `SingleGateKind` enum).

        Example:
        ```mlir
        qref.single h %q : !qcc.qubit_ref
        qref.single rz(%theta) %q : f64, !qcc.qubit_ref
        qref.single u_zxz(%z1, %x, %z2) %q : f64, !qcc.qubit_ref
        ```
    }];

  let arguments = (ins Qcc_SingleGateKindAttr:$gate_kind,
                       QRef_QubitArg<"the qubit to act on">:$qubit,
                       Variadic<Qcc_GateParam>:$params);

  let assemblyFormat = [{
        $gate_kind (`(` $params^ `)`)? $qubit attr-dict `:`
        custom<GateTypes>(type($params), ref($params), type($qubit))
    }];

  let builders = [
    // A gate without parameters.
    OpBuilder<(ins "::qcc::SingleGateKind":$gateKind, "::mlir::Value":$qubit), [{
      build($_builder, $_state, gateKind, qubit, ::mlir::ValueRange());
    }]>
  ];

  let hasVerifier = 1;
}

def QRef_PairOp : QRef_Op<"pair", [AllTypesMatch<["lhs", "rhs"]>]> {
  let summary = "two-qubit gate";
  let description = [{
        Applies a two-qubit gate to the distinct qubits `lhs` and `rhs`. For controlled gates `lhs` is the control.

        A parametrised gate takes its angles (radians) as operands (see also the `PairGateKind` enum).

        It is undefined behaviour if `lhs` and `rhs` refer to the same qubit.

        Example:
        ```mlir
        qref.pair cx %c, %t : !qcc.qubit_ref
        qref.pair rzz(%theta) %a, %b : f64, !qcc.qubit_ref
        ```
    }];

  let arguments = (ins Qcc_PairGateKindAttr:$gate_kind,
                       QRef_QubitArg<"the first qubit to act on">:$lhs,
                       QRef_QubitArg<"the second qubit to act on">:$rhs,
                       Variadic<Qcc_GateParam>:$params);

  let assemblyFormat = [{
        $gate_kind (`(` $params^ `)`)? $lhs `,` $rhs attr-dict `:`
        custom<GateTypes>(type($params), ref($params), type($lhs))
    }];

  let builders = [
    // A gate without parameters.
    OpBuilder<(ins "::qcc::PairGateKind":$gateKind, "::mlir::Value":$lhs, "::mlir::Value":$rhs), [{
      build($_builder, $_state, gateKind, lhs, rhs, ::mlir::ValueRange());
    }]>
  ];

  let hasVerifier = 1;
}

def QRef_MeasureOp : QRef_Op<"measure"> {
  let summary = "measures a qubit";
  let description = [{
        Measures `qubit` in the given basis, which projects its state. Returns the outcome as a classical bit: `z`
        measures in the computational basis (|0⟩ gives 0, |1⟩ gives 1), `x` in the basis |+⟩, |−⟩ (|+⟩ gives 0, |−⟩
        gives 1).

        Example:
        ```mlir
        %bit = qref.measure z %q : !qcc.qubit_ref -> i1
        ```
    }];

  let arguments = (ins Qcc_BasisAttr:$basis,
                       QRef_QubitArg<"the qubit to measure">:$qubit);
  let results = (outs I1:$bit);

  let assemblyFormat = [{
        $basis $qubit attr-dict `:` type($qubit) `->` type($bit)
    }];

  let builders = [
    OpBuilder<(ins "::qcc::Basis":$basis, "::mlir::Value":$qubit), [{
      build($_builder, $_state, $_builder.getI1Type(), basis, qubit);
    }]>
  ];
}

def QRef_ResetOp : QRef_Op<"reset"> {
  let summary = "resets a qubit to a basis state";
  let description = [{
        Resets `qubit` to the first state of the given basis: `z` sends it to |0⟩, `x` to |+⟩.

        Example:
        ```mlir
        qref.reset z %q : !qcc.qubit_ref
        ```
    }];

  let arguments = (ins Qcc_BasisAttr:$basis,
                       QRef_QubitArg<"the qubit to reset">:$qubit);

  let assemblyFormat = [{
        $basis $qubit attr-dict `:` type($qubit)
    }];
}

#endif // INCLUDE_QCC_DIALECT_QREF_IR_QREFOPS_TD_
