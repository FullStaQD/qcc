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

include "qcc/Dialect/QVec/IR/QVecAttrs.td"
include "qcc/Dialect/QVec/IR/QVecDialect.td"
include "qcc/Dialect/QVec/IR/QVecInterfaces.td"
include "qcc/Dialect/QVec/IR/QVecTypes.td"

include "mlir/IR/OpBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// QVec operations
//===----------------------------------------------------------------------===//

// TODO: The memory effects we use here are probably too conservative. We have them here to protect our ops against
// quantum-unaware passes. Note that e.g. a `Pure` measurement would allow some passes to hoist them out of control-flow
// or alternatively sink into control-flow (see code motion) under circumstances were this is not consistent with the
// intended semantics.
class QVec_Op<string mnemonic, list<Trait> traits = []>
    : Op<QVec_Dialect, mnemonic,
         !listconcat(traits, [MemoryEffects<[MemRead, MemWrite]>, QVec_QubitLaneOpInterface])>;

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
        %qs_out = qvec.single h %qs : vector<4x!qco.qubit>
        %qs_rz = qvec.single rz(%theta) %qs : vector<4x!qco.qubit>, vector<4xf64>
        %qs_u = qvec.single u_zxz(%z1, %x, %z2) %qs : vector<4x!qco.qubit>, vector<4xf64>
        ```
    }];

  let arguments = (ins QVec_SingleGateKindAttr:$gate_kind,
                       QVec_QubitVector:$qubits_in,
                       Variadic<QVec_AngleVector>:$params);
  let results = (outs QVec_QubitVector:$qubits_out);

  let assemblyFormat = [{
        $gate_kind (`(` $params^ `)`)? $qubits_in attr-dict `:`
        custom<GateTypes>(type($qubits_in), type($params), ref($params))
    }];

  let builders = [
    OpBuilder<(ins "::qcc::qvec::SingleGateKind":$gateKind, "::mlir::Value":$qubitsIn,
                   CArg<"::mlir::ValueRange", "{}">:$params), [{
      build($_builder, $_state, qubitsIn.getType(), gateKind, qubitsIn, params);
    }]>
  ];

  let hasVerifier = 1;

  let extraClassDeclaration = [{
        /// The gate acts on one qubit, hence one lane.
        unsigned getNumQubitLanes() { return 1; }

        ::mlir::TypedValue<::mlir::VectorType> getQubitOperand(unsigned lane) {
          assert(lane == 0 && "no such qubit lane");
          return getQubitsIn();
        }

        ::mlir::TypedValue<::mlir::VectorType> getQubitResult(unsigned lane) {
          assert(lane == 0 && "no such qubit lane");
          return getQubitsOut();
        }
    }];
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
        %cs_out, %ts_out = qvec.pair cx %ctrls, %tgts : vector<4x!qco.qubit>
        %as_out, %bs_out = qvec.pair rzz(%theta) %as, %bs : vector<4x!qco.qubit>, vector<4xf64>
        ```
    }];

  let arguments = (ins QVec_PairGateKindAttr:$gate_kind,
                       QVec_QubitVector:$lhs_in,
                       QVec_QubitVector:$rhs_in,
                       Variadic<QVec_AngleVector>:$params);
  let results = (outs QVec_QubitVector:$lhs_out,
                      QVec_QubitVector:$rhs_out);

  let assemblyFormat = [{
        $gate_kind (`(` $params^ `)`)? $lhs_in `,` $rhs_in attr-dict `:`
        custom<GateTypes>(type($lhs_in), type($params), ref($params))
    }];

  let builders = [
    OpBuilder<(ins "::qcc::qvec::PairGateKind":$gateKind, "::mlir::Value":$lhsIn, "::mlir::Value":$rhsIn,
                   CArg<"::mlir::ValueRange", "{}">:$params), [{
      build($_builder, $_state, lhsIn.getType(), rhsIn.getType(), gateKind, lhsIn, rhsIn, params);
    }]>
  ];

  let hasVerifier = 1;

  let extraClassDeclaration = [{
        /// The gate acts on two qubits: lane 0 is the left operand, lane 1 the right one.
        unsigned getNumQubitLanes() { return 2; }

        ::mlir::TypedValue<::mlir::VectorType> getQubitOperand(unsigned lane) {
          assert(lane < 2 && "no such qubit lane");
          return lane == 0 ? getLhsIn() : getRhsIn();
        }

        ::mlir::TypedValue<::mlir::VectorType> getQubitResult(unsigned lane) {
          assert(lane < 2 && "no such qubit lane");
          return lane == 0 ? getLhsOut() : getRhsOut();
        }
    }];
}

def QVec_GlobalOp : QVec_Op<"global", [AllTypesMatch<["qubits_in", "qubits_out"]>]> {
  let summary = "gate acting on all qubits of a vector jointly";
  let description = [{
        Unlike `single` and `pair`, which apply one gate per lane, a `global` gate acts on all lanes of its qubit vector
        *jointly*. The gate is parametrised by a square matrix over the lanes.

        For example the `zz` global gate with the `n x n` angle matrix `A` applies

            exp(-i/4 * sum_{i != j} A_ij Z_i Z_j).

        `A` must be symmetric with a zero diagonal; the verifier checks this for constant matrices. Note that
        `rzz(theta)` between lanes `i` and `j` corresponds to `A_ij = A_ji = theta`.

        Example:
        ```mlir
        %qs_out = qvec.global zz(%A) %qs : vector<4x!qco.qubit>, vector<4x4xf64>
        ```
    }];

  let arguments = (ins QVec_GlobalGateKindAttr:$gate_kind,
                       QVec_QubitVector:$qubits_in,
                       QVec_AngleMatrix:$angles);
  let results = (outs QVec_QubitVector:$qubits_out);

  let assemblyFormat = [{
        $gate_kind `(` $angles `)` $qubits_in attr-dict `:` type($qubits_in) `,` type($angles)
    }];

  let builders = [
    OpBuilder<(ins "::qcc::qvec::GlobalGateKind":$gateKind, "::mlir::Value":$qubitsIn, "::mlir::Value":$angles), [{
      build($_builder, $_state, qubitsIn.getType(), gateKind, qubitsIn, angles);
    }]>
  ];

  let hasVerifier = 1;

  let extraClassDeclaration = [{
        /// One lane: the gate maps the whole vector to the whole vector.
        unsigned getNumQubitLanes() { return 1; }

        ::mlir::TypedValue<::mlir::VectorType> getQubitOperand(unsigned lane) {
          assert(lane == 0 && "no such qubit lane");
          return getQubitsIn();
        }

        ::mlir::TypedValue<::mlir::VectorType> getQubitResult(unsigned lane) {
          assert(lane == 0 && "no such qubit lane");
          return getQubitsOut();
        }
    }];
}

def QVec_MZOp : QVec_Op<"mz", [AllTypesMatch<["qubits_in", "qubits_out"]>,
                               AllShapesMatch<["qubits_in", "bits"]>]> {
  let summary = "measures a vector of qubits in the computational basis";
  let description = [{
        Measures every element of `qubits_in` in the computational (Z) basis, collapsing their state,
        and yields the measured qubits plus one classical bit per element.

        Example:
        ```mlir
        %qs_out, %r = qvec.mz %qs : vector<4x!qco.qubit> -> vector<4xi1>
        ```
    }];

  let arguments = (ins QVec_QubitVector:$qubits_in);
  let results = (outs QVec_QubitVector:$qubits_out,
                      QVec_BitVector:$bits);

  let assemblyFormat = [{
        $qubits_in attr-dict `:` type($qubits_in) `->` type($bits)
    }];

  let extraClassDeclaration = [{
        /// One lane for the measured qubits. `bits` is classical and hence outside the lanes.
        unsigned getNumQubitLanes() { return 1; }

        ::mlir::TypedValue<::mlir::VectorType> getQubitOperand(unsigned lane) {
          assert(lane == 0 && "no such qubit lane");
          return getQubitsIn();
        }

        ::mlir::TypedValue<::mlir::VectorType> getQubitResult(unsigned lane) {
          assert(lane == 0 && "no such qubit lane");
          return getQubitsOut();
        }
    }];
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECOPS_TD_
