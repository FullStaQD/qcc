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
include "qcc/Dialect/QVec/IR/QVecTypes.td"

include "mlir/IR/OpBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// QVec operations
//===----------------------------------------------------------------------===//

// FIXME: update all docs in the end.

// FIXME: should we really have MemoryEffects? What about pure?
class QVecOp<string mnemonic, list<Trait> traits = []>
    : Op<QVecDialect, mnemonic,
         !listconcat(traits, [MemoryEffects<[MemRead, MemWrite]>])>;

def SingleOp : QVecOp<"single", [AllTypesMatch<["qubits_in", "qubits_out"]>]> {
  let summary = "Apply one single-qubit gate across a vector of qubits.";
  let description = [{
        Applies `gate` to every element of `qubits_in` and returns the qubits it acted on. The
        intent is that a target implements this as a single instruction; on HiSEP-Q it lowers to one
        `QV.SINGLE`, whose `GateID` field takes the gate kind and whose `vs1` register holds the
        qubit indices.

        FIXME: should be "canonicalized"
        The elements of one operation must be distinct qubits. Because they are distinct and carry
        the same gate, they commute, which is what makes element order a free choice; the canonical
        form sorts elements ascending by qubit index.

        Example:
        ```mlir
        %qs_out = qvec.single h %qs : vector<4x!qco.qubit>
        ```
    }];

  let arguments = (ins QVec_SingleGateAttr:$gate_kind,
                       QVec_QubitVector:$qubits_in);
  let results = (outs QVec_QubitVector:$qubits_out);

  let assemblyFormat = [{
        `` $gate_kind $qubits_in attr-dict `:` type($qubits_in)
    }];
}

def PairOp : QVecOp<"pair", [AllTypesMatch<["ctrls_in", "tgts_in", "ctrls_out", "tgts_out"]>]> {
  let summary = "Apply one two-qubit gate across two vectors of qubits.";
  let description = [{
        Applies `gate` to every element and returns the qubits it acted on, one vector per operand.
        Element `i` of `ctrls_in` and element `i` of `tgts_in` are the control and the target of the
        same gate, so the two vectors necessarily have the same length.

        Control-before-target is this dialect's order, chosen because that is how the gates read.
        A target whose encoding disagrees has to swap in its lowering: HiSEP-Q's `QV.PAIR` puts the
        targets in `vs1` and the controls in `vs2`, so `ConvertQVecToHiSEPQIntrinsics` swaps them.

        All 2N qubits named by one operation must be distinct. The canonical form sorts elements
        ascending by control index, carrying each element's target along with it.

        Example:
        ```mlir
        %cs_out, %ts_out = qvec.pair cx %ctrls, %tgts : vector<4x!qco.qubit>
        ```
    }];

  // FIXME: rename ctrls and tgts. Misleading for things like iSWAP.
  let arguments = (ins QVec_PairGateAttr:$gate_kind,
                       QVec_QubitVector:$ctrls_in,
                       QVec_QubitVector:$tgts_in);
  let results = (outs QVec_QubitVector:$ctrls_out,
                      QVec_QubitVector:$tgts_out);

  let assemblyFormat = [{
        `` $gate_kind $ctrls_in `,` $tgts_in attr-dict `:` type($ctrls_in)
    }];
}

def MzOp : QVecOp<"mz", [AllTypesMatch<["qubits_in", "qubits_out"]>,
                           AllShapesMatch<["qubits_in", "bits"]>]> {
  let summary = "Measure a vector of qubits in the computational basis.";
  let description = [{
        Measures every element of `qubits_in` in the computational (Z) basis, collapsing their state,
        and yields the measured qubits plus one classical bit per element.

        The qubits come back so that the SSA chain continues past the measurement. They carry the
        collapsed post-measurement state, matching the bit each one produced; this is not a reset,
        so reusing them as fresh ancillas needs an explicit one.

        Measurement gets its own operation even where a target encodes it as a single-qubit gate --
        HiSEP-Q does, as a SINGLE-class instruction (`QV_MZ_FUNCT7`). Folding it into `qvec.single`
        would make every later question of the form "is this operation unitary?" answerable only by
        inspecting the gate attribute, which is a bad trade for matching one encoding.

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
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECOPS_TD_
