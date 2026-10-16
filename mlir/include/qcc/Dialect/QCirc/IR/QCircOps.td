// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCIRC_IR_QCIRCOPS_TD_
#define INCLUDE_QCC_DIALECT_QCIRC_IR_QCIRCOPS_TD_

include "qcc/Dialect/QCirc/IR/QCircAttrs.td"
include "qcc/Dialect/QCirc/IR/QCircDialect.td"
include "qcc/Dialect/Qcc/IR/QccInterfaces.td"
include "qcc/Dialect/Qcc/IR/QccTypes.td"

include "mlir/IR/CommonTypeConstraints.td"
include "mlir/IR/OpBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// QCirc type constraints
//===----------------------------------------------------------------------===//

// An angle in radians.
def QCirc_Angle : AnyTypeOf<[F64], "64-bit float angle">;

//===----------------------------------------------------------------------===//
// QCirc operations
//===----------------------------------------------------------------------===//

// No memory effects, but deliberately not `Pure`: qubit values must never be duplicated.
class QCirc_Op<string mnemonic, list<Trait> traits = []>
    : Op<QCirc_Dialect, mnemonic,
         !listconcat(traits, [NoMemoryEffect, Qcc_NoMultiUseQubits, Qcc_QubitLaneOpInterface])>;

def QCirc_SingleOp : QCirc_Op<"single", [AllTypesMatch<["qubit_in", "qubit_out"]>]> {
  let summary = "single-qubit gate";
  let description = [{
        Applies a single-qubit gate to a qubit.

        A parametrised gate takes its angles (radians) as operands. How many it takes is fixed per gate kind (see the
        `SingleGateKind` enum).

        Example:
        ```mlir
        %q1 = qcirc.single h %q0 : !qcc.qubit
        %q2 = qcirc.single rz(%theta) %q1 : f64, !qcc.qubit
        %q3 = qcirc.single u_zxz(%z1, %x, %z2) %q2 : f64, !qcc.qubit
        ```
    }];

  let arguments = (ins QCirc_SingleGateKindAttr:$gate_kind,
                       Qcc_QubitType:$qubit_in,
                       Variadic<QCirc_Angle>:$params);
  let results = (outs Qcc_QubitType:$qubit_out);

  let assemblyFormat = [{
        $gate_kind (`(` $params^ `)`)? $qubit_in attr-dict `:`
        custom<GateTypes>(type($params), ref($params), type($qubit_in))
    }];

  let builders = [
    OpBuilder<(ins "::qcc::qcirc::SingleGateKind":$gateKind, "::mlir::Value":$qubitIn,
                   CArg<"::mlir::ValueRange", "{}">:$params), [{
      build($_builder, $_state, qubitIn.getType(), gateKind, qubitIn, params);
    }]>
  ];

  let hasVerifier = 1;
}

def QCirc_PairOp : QCirc_Op<"pair", [AllTypesMatch<["lhs_in", "rhs_in", "lhs_out", "rhs_out"]>]> {
  let summary = "two-qubit gate";
  let description = [{
        Applies a two-qubit gate to the qubits `lhs` and `rhs`. For controlled gates `lhs` is the control.

        A parametrised gate takes its angles (radians) as operands (see also the `PairGateKind` enum).

        Example:
        ```mlir
        %c1, %t1 = qcirc.pair cx %c0, %t0 : !qcc.qubit
        %a1, %b1 = qcirc.pair rzz(%theta) %a0, %b0 : f64, !qcc.qubit
        ```
    }];

  let arguments = (ins QCirc_PairGateKindAttr:$gate_kind,
                       Qcc_QubitType:$lhs_in,
                       Qcc_QubitType:$rhs_in,
                       Variadic<QCirc_Angle>:$params);
  let results = (outs Qcc_QubitType:$lhs_out,
                      Qcc_QubitType:$rhs_out);

  let assemblyFormat = [{
        $gate_kind (`(` $params^ `)`)? $lhs_in `,` $rhs_in attr-dict `:`
        custom<GateTypes>(type($params), ref($params), type($lhs_in))
    }];

  let builders = [
    OpBuilder<(ins "::qcc::qcirc::PairGateKind":$gateKind, "::mlir::Value":$lhsIn, "::mlir::Value":$rhsIn,
                   CArg<"::mlir::ValueRange", "{}">:$params), [{
      build($_builder, $_state, lhsIn.getType(), rhsIn.getType(), gateKind, lhsIn, rhsIn, params);
    }]>
  ];

  let hasVerifier = 1;
}

def QCirc_MeasureOp : QCirc_Op<"measure", [AllTypesMatch<["qubit_in", "qubit_out"]>]> {
  let summary = "measures a qubit";
  let description = [{
        Measures a qubit in the given basis, which projects its state, and yields the measured qubit plus the outcome
        as a classical bit: `z` measures in the computational basis (|0⟩ gives 0, |1⟩ gives 1), `x` in the basis
        |+⟩, |−⟩ (|+⟩ gives 0, |−⟩ gives 1).

        Example:
        ```mlir
        %q1, %bit = qcirc.measure z %q0 : !qcc.qubit -> i1
        ```
    }];

  let arguments = (ins QCirc_BasisAttr:$basis,
                       Qcc_QubitType:$qubit_in);
  let results = (outs Qcc_QubitType:$qubit_out,
                      I1:$bit);

  let assemblyFormat = [{
        $basis $qubit_in attr-dict `:` type($qubit_in) `->` type($bit)
    }];

  let builders = [
    OpBuilder<(ins "::qcc::qcirc::Basis":$basis, "::mlir::Value":$qubitIn), [{
      build($_builder, $_state, qubitIn.getType(), $_builder.getI1Type(), basis, qubitIn);
    }]>
  ];
}

def QCirc_ResetOp : QCirc_Op<"reset", [AllTypesMatch<["qubit_in", "qubit_out"]>]> {
  let summary = "resets a qubit to a basis state";
  let description = [{
        Resets a qubit to the first state of the given basis: `z` sends it to |0⟩, `x` to |+⟩.

        Example:
        ```mlir
        %q1 = qcirc.reset z %q0 : !qcc.qubit
        ```
    }];

  let arguments = (ins QCirc_BasisAttr:$basis,
                       Qcc_QubitType:$qubit_in);
  let results = (outs Qcc_QubitType:$qubit_out);

  let assemblyFormat = [{
        $basis $qubit_in attr-dict `:` type($qubit_in)
    }];

  let builders = [
    OpBuilder<(ins "::qcc::qcirc::Basis":$basis, "::mlir::Value":$qubitIn), [{
      build($_builder, $_state, qubitIn.getType(), basis, qubitIn);
    }]>
  ];
}

#endif // INCLUDE_QCC_DIALECT_QCIRC_IR_QCIRCOPS_TD_
