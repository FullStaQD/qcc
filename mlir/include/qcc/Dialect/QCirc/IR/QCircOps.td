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

// `tensor<NxNxf64>` - one angle (radians) per pair of qubits. The shape is static, so that it can be checked against
// the number of qubits.
def QCirc_AngleMatrix : RankedTensorOf<[F64], [HasAnyRankOfPred<[2]>, HasStaticShapePred],
                                       "statically shaped 2D tensor">;

//===----------------------------------------------------------------------===//
// QCirc operations
//===----------------------------------------------------------------------===//

// All ops are free of memory effects, but deliberately not `Pure`: the qubit values are affine, so folding or hoisting
// must never duplicate them.
class QCirc_Op<string mnemonic, list<Trait> traits = []>
    : Op<QCirc_Dialect, mnemonic,
         !listconcat(traits, [NoMemoryEffect, Qcc_SingleUseQubits, Qcc_QubitLaneOpInterface])>;

def QCirc_SingleOp : QCirc_Op<"single", [AllTypesMatch<["qubit_in", "qubit_out"]>]> {
  let summary = "single-qubit gate";
  let description = [{
        Applies a single-qubit gate to a qubit.

        A parametrised gate takes its angles (radians) as operands. How many it takes is fixed per gate kind (see the
        `SingleGateKind` enum). The angles share one type, which is spelled once.

        Example:
        ```mlir
        %q1 = qcirc.single h %q0 : !qcc.qubit
        %q2 = qcirc.single rz(%theta) %q1 : !qcc.qubit, f64
        %q3 = qcirc.single u_zxz(%z1, %x, %z2) %q2 : !qcc.qubit, f64
        ```
    }];

  let arguments = (ins QCirc_SingleGateKindAttr:$gate_kind,
                       Qcc_QubitType:$qubit_in,
                       Variadic<QCirc_Angle>:$params);
  let results = (outs Qcc_QubitType:$qubit_out);

  let assemblyFormat = [{
        $gate_kind (`(` $params^ `)`)? $qubit_in attr-dict `:`
        custom<GateTypes>(type($qubit_in), type($params), ref($params))
    }];

  let builders = [
    OpBuilder<(ins "::qcc::qcirc::SingleGateKind":$gateKind, "::mlir::Value":$qubitIn,
                   CArg<"::mlir::ValueRange", "{}">:$params), [{
      build($_builder, $_state, qubitIn.getType(), gateKind, qubitIn, params);
    }]>
  ];

  let hasVerifier = 1;

  let extraClassDeclaration = [{
        /// One lane: the qubit the gate acts on.
        ::mlir::OperandRange getQubitOperands() { return getODSOperands(0); }
        ::mlir::ResultRange getQubitResults() { return getODSResults(0); }
    }];
}

def QCirc_PairOp : QCirc_Op<"pair", [AllTypesMatch<["lhs_in", "rhs_in", "lhs_out", "rhs_out"]>]> {
  let summary = "two-qubit gate";
  let description = [{
        Applies a two-qubit gate to the qubits `lhs` and `rhs`. For controlled gates `lhs` is the control.

        A parametrised gate takes its angles (radians) as operands, exactly as `qcirc.single` does (see also the
        `PairGateKind` enum). The two qubits share one type, which is spelled once.

        Example:
        ```mlir
        %c1, %t1 = qcirc.pair cx %c0, %t0 : !qcc.qubit
        %a1, %b1 = qcirc.pair rzz(%theta) %a0, %b0 : !qcc.qubit, f64
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
        custom<GateTypes>(type($lhs_in), type($params), ref($params))
    }];

  let builders = [
    OpBuilder<(ins "::qcc::qcirc::PairGateKind":$gateKind, "::mlir::Value":$lhsIn, "::mlir::Value":$rhsIn,
                   CArg<"::mlir::ValueRange", "{}">:$params), [{
      build($_builder, $_state, lhsIn.getType(), rhsIn.getType(), gateKind, lhsIn, rhsIn, params);
    }]>
  ];

  let hasVerifier = 1;

  let extraClassDeclaration = [{
        /// Two lanes: lane 0 is `lhs`, lane 1 is `rhs`.
        ::mlir::OperandRange getQubitOperands() { return getOperation()->getOperands().take_front(2); }
        ::mlir::ResultRange getQubitResults() { return getOperation()->getResults(); }
    }];
}

def QCirc_GlobalOp : QCirc_Op<"global"> {
  let summary = "gate acting on several qubits jointly";
  let description = [{
        Unlike `single` and `pair`, a `global` gate acts on any number of qubits *jointly*. The gate is parametrised by
        a square matrix over its qubits, in operand order.

        For example the `zz` global gate with the `n x n` angle matrix `A` applies

            exp(-i/4 * sum_{i != j} A_ij Z_i Z_j).

        `A` must be symmetric with a zero diagonal; the verifier checks this for constant matrices. Note that
        `rzz(theta)` between the qubits `i` and `j` corresponds to `A_ij = A_ji = theta`.

        The matrix is a statically shaped tensor, so that its shape is checked against the number of qubits. The
        qubits share one type, which is spelled once.

        Example:
        ```mlir
        %a1, %b1, %c1 = qcirc.global zz(%A) %a0, %b0, %c0 : !qcc.qubit, tensor<3x3xf64>
        ```
    }];

  let arguments = (ins QCirc_GlobalGateKindAttr:$gate_kind,
                       Variadic<Qcc_QubitType>:$qubits_in,
                       QCirc_AngleMatrix:$angles);
  let results = (outs Variadic<Qcc_QubitType>:$qubits_out);

  let assemblyFormat = [{
        $gate_kind `(` $angles `)` $qubits_in attr-dict `:`
        custom<GlobalQubitTypes>(type($qubits_in), type($qubits_out), ref($qubits_in)) `,` type($angles)
    }];

  let builders = [
    OpBuilder<(ins "::qcc::qcirc::GlobalGateKind":$gateKind, "::mlir::ValueRange":$qubitsIn,
                   "::mlir::Value":$angles), [{
      build($_builder, $_state, qubitsIn.getTypes(), gateKind, qubitsIn, angles);
    }]>
  ];

  let hasVerifier = 1;

  let extraClassDeclaration = [{
        /// One lane per qubit, in operand order.
        ::mlir::OperandRange getQubitOperands() { return getQubitsIn(); }
        ::mlir::ResultRange getQubitResults() { return getQubitsOut(); }
    }];
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

  let extraClassDeclaration = [{
        /// One lane: the measured qubit. `bit` is classical and hence outside the lanes.
        ::mlir::OperandRange getQubitOperands() { return getODSOperands(0); }
        ::mlir::ResultRange getQubitResults() { return getODSResults(0); }
    }];
}

def QCirc_ResetOp : QCirc_Op<"reset", [AllTypesMatch<["qubit_in", "qubit_out"]>]> {
  let summary = "resets a qubit to a basis state";
  let description = [{
        Resets a qubit to the first state of the given basis, whatever its state was: `z` sends it to |0⟩, `x` to
        |+⟩.

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

  let extraClassDeclaration = [{
        /// One lane: the qubit that is reset.
        ::mlir::OperandRange getQubitOperands() { return getODSOperands(0); }
        ::mlir::ResultRange getQubitResults() { return getODSResults(0); }
    }];
}

#endif // INCLUDE_QCC_DIALECT_QCIRC_IR_QCIRCOPS_TD_
