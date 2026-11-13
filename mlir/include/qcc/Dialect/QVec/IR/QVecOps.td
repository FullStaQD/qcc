// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QVEC_IR_QVECOPS_TD_
#define INCLUDE_QCC_DIALECT_QVEC_IR_QVECOPS_TD_

include "qcc/Dialect/QVec/IR/QVecDialect.td"
include "qcc/Dialect/QVec/IR/QVecTypes.td"
include "qcc/Dialect/Qcc/IR/QccAttrs.td"
include "qcc/Dialect/Qcc/IR/QccInterfaces.td"

include "mlir/IR/OpBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// QVec operations
//===----------------------------------------------------------------------===//

// TODO: The memory effects we use here are probably too conservative. We have them here to protect our ops against
// quantum-unaware passes. Note that e.g. a `Pure` measurement would allow some passes to hoist them out of control-flow
// or alternatively sink into control-flow (see code motion) under circumstances where this is not consistent with the
// intended semantics.
class QVec_Op<string mnemonic, list<Trait> traits = []>
    : Op<QVec_Dialect, mnemonic,
         !listconcat(traits, [MemoryEffects<[MemRead, MemWrite]>, Qcc_QubitLaneOpInterface])>;

def QVec_SingleOp : QVec_Op<"single", [AllTypesMatch<["qubits_in", "qubits_out"]>]> {
  let summary = "single-qubit gate across a vector of qubits";
  let description = [{
        A `single` applies the same gate over all qubits referenced in its operand vector. Each element of the vector
        must be distinct, consistent with the linearly typed qubit type.

        Parametrised gates take their angles as vectors that are lane-aligned with the qubit vector: lane `i` is
        rotated by `params[k][i]`. How many parameter vectors a gate kind takes is fixed per kind (see the
        `SingleGateKind` enum).

        Example:
        ```mlir
        %qs_out = qvec.single h %qs : vector<4x!qcc.qubit>
        %qs_rz = qvec.single rz(%theta) %qs : vector<4xf64>, vector<4x!qcc.qubit>
        %qs_u = qvec.single u_zxz(%z1, %x, %z2) %qs : vector<4xf64>, vector<4x!qcc.qubit>
        ```
    }];

  let arguments = (ins Qcc_SingleGateKindAttr:$gate_kind,
                       QVec_QubitVector:$qubits_in,
                       Variadic<QVec_AngleVector>:$params);
  let results = (outs QVec_QubitVector:$qubits_out);

  let assemblyFormat = [{
        $gate_kind (`(` $params^ `)`)? $qubits_in attr-dict `:`
        custom<GateTypes>(type($params), ref($params), type($qubits_in))
    }];

  let builders = [
    OpBuilder<(ins "::qcc::SingleGateKind":$gateKind, "::mlir::Value":$qubitsIn,
                   CArg<"::mlir::ValueRange", "{}">:$params), [{
      build($_builder, $_state, qubitsIn.getType(), gateKind, qubitsIn, params);
    }]>
  ];

  let hasVerifier = 1;
}

def QVec_PairOp : QVec_Op<"pair", [AllTypesMatch<["lhs_in", "rhs_in", "lhs_out", "rhs_out"]>]> {
  let summary = "two-qubit gate across two vectors of qubits";
  let description = [{
        Applies a two-qubit gate to each pair of qubits `lhs[i]` and `rhs[i]`. All qubits must be distinct, consistent
        with a linearly typed qubit. For controlled gates the left operand holds the controls.

        Parametrised gates take their angles as vectors that are lane-aligned with the qubit vectors, exactly as
        `qvec.single` does (see also `PairGateKind` enum).

        Example:
        ```mlir
        %cs_out, %ts_out = qvec.pair cx %ctrls, %tgts : vector<4x!qcc.qubit>
        %as_out, %bs_out = qvec.pair rzz(%theta) %as, %bs : vector<4xf64>, vector<4x!qcc.qubit>
        ```
    }];

  let arguments = (ins Qcc_PairGateKindAttr:$gate_kind,
                       QVec_QubitVector:$lhs_in,
                       QVec_QubitVector:$rhs_in,
                       Variadic<QVec_AngleVector>:$params);
  let results = (outs QVec_QubitVector:$lhs_out,
                      QVec_QubitVector:$rhs_out);

  let assemblyFormat = [{
        $gate_kind (`(` $params^ `)`)? $lhs_in `,` $rhs_in attr-dict `:`
        custom<GateTypes>(type($params), ref($params), type($lhs_in))
    }];

  let builders = [
    OpBuilder<(ins "::qcc::PairGateKind":$gateKind, "::mlir::Value":$lhsIn, "::mlir::Value":$rhsIn,
                   CArg<"::mlir::ValueRange", "{}">:$params), [{
      build($_builder, $_state, lhsIn.getType(), rhsIn.getType(), gateKind, lhsIn, rhsIn, params);
    }]>
  ];

  let hasVerifier = 1;
}

def QVec_MeasureOp : QVec_Op<"measure", [AllTypesMatch<["qubits_in", "qubits_out"]>,
                                         AllShapesMatch<["qubits_in", "bits"]>]> {
  let summary = "measures a vector of qubits";
  let description = [{
        Measures every element of `qubits_in` in the given basis, which projects its state, and yields the measured
        qubits plus one classical bit per element: `z` measures in the computational basis (|0⟩ gives 0, |1⟩ gives 1),
        `x` in the basis |+⟩, |−⟩ (|+⟩ gives 0, |−⟩ gives 1).

        Example:
        ```mlir
        %qs_out, %bits = qvec.measure z %qs : vector<4x!qcc.qubit> -> vector<4xi1>
        ```
    }];

  let arguments = (ins Qcc_BasisAttr:$basis,
                       QVec_QubitVector:$qubits_in);
  let results = (outs QVec_QubitVector:$qubits_out,
                      QVec_BitVector:$bits);

  let assemblyFormat = [{
        $basis $qubits_in attr-dict `:` type($qubits_in) `->` type($bits)
    }];

  let builders = [
    // One bit per qubit.
    OpBuilder<(ins "::qcc::Basis":$basis, "::mlir::Value":$qubitsIn), [{
      auto qubitsType = ::llvm::cast<::mlir::VectorType>(qubitsIn.getType());
      build($_builder, $_state, qubitsType, qubitsType.clone($_builder.getI1Type()), basis, qubitsIn);
    }]>
  ];
}

def QVec_ResetOp : QVec_Op<"reset", [AllTypesMatch<["qubits_in", "qubits_out"]>]> {
  let summary = "resets a vector of qubits to a basis state";
  let description = [{
        Resets every element of `qubits_in` to the first state of the given basis: `z` sends it to |0⟩, `x` to |+⟩.

        Example:
        ```mlir
        %qs_out = qvec.reset z %qs : vector<4x!qcc.qubit>
        ```
    }];

  let arguments = (ins Qcc_BasisAttr:$basis,
                       QVec_QubitVector:$qubits_in);
  let results = (outs QVec_QubitVector:$qubits_out);

  let assemblyFormat = [{
        $basis $qubits_in attr-dict `:` type($qubits_in)
    }];

  let builders = [
    OpBuilder<(ins "::qcc::Basis":$basis, "::mlir::Value":$qubitsIn), [{
      build($_builder, $_state, qubitsIn.getType(), basis, qubitsIn);
    }]>
  ];
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECOPS_TD_
