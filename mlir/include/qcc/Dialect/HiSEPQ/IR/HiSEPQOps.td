// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQOPS_TD_
#define INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQOPS_TD_

include "qcc/Dialect/HiSEPQ/IR/HiSEPQAttrs.td"
include "qcc/Dialect/HiSEPQ/IR/HiSEPQDialect.td"
include "qcc/Dialect/HiSEPQ/IR/HiSEPQTypes.td"

include "mlir/IR/OpBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// HiSEP-Q operations
//===----------------------------------------------------------------------===//

// FIXME: update all docs in the end.

// FIXME: should we really have MemoryEffects? What about pure?
class HiSEPQOp<string mnemonic, list<Trait> traits = []>
    : Op<HiSEPQDialect, mnemonic,
         !listconcat(traits, [MemoryEffects<[MemRead, MemWrite]>])>;

def SingleOp : HiSEPQOp<"single", [AllTypesMatch<["qubits_in", "qubits_out"]>]> {
  let summary = "Apply one single-qubit gate across a vector of qubits.";
  let description = [{
        Applies `gate` to every element of `qubits_in` and returns the qubits it acted on. This is
        one `QV.SINGLE` instruction: the gate kind occupies the instruction's `GateID` field and the
        qubit indices live in the vector register named by `vs1`.

        FIXME: should be "canonicalized"
        The elements of one operation must be distinct qubits. Because they are distinct and carry
        the same gate, they commute, which is what makes element order a free choice; the canonical
        form sorts elements ascending by qubit index.

        Example:
        ```mlir
        %qs_out = hisepq.single h %qs : vector<4x!qco.qubit>
        ```
    }];

  let arguments = (ins HiSEPQ_SingleGateAttr:$gate, // FIXME: should probably be $gate_kind
                       HiSEPQ_QubitVector:$qubits_in);
  let results = (outs HiSEPQ_QubitVector:$qubits_out);

  let assemblyFormat = [{
        `` $gate $qubits_in attr-dict `:` type($qubits_in)
    }];
}

def PairOp : HiSEPQOp<"pair", [AllTypesMatch<["ctrls_in", "tgts_in", "ctrls_out", "tgts_out"]>]> {
  let summary = "Apply one two-qubit gate across two vectors of qubits.";
  let description = [{
        Applies `gate` to every element and returns the qubits it acted on, one vector per operand.
        Element `i` of `ctrls_in` and element `i` of `tgts_in` are the control and the target of the
        same gate, so the two vectors necessarily have the same length.

        This is one `QV.PAIR` instruction. Beware that the encoding orders the registers the other
        way round -- `vs1` holds the targets and `vs2` the sources/controls -- so a lowering has to
        swap. We keep control-before-target here because that is how the gates read.

        All 2N qubits named by one operation must be distinct. The canonical form sorts elements
        ascending by control index, carrying each element's target along with it.

        Example:
        ```mlir
        %cs_out, %ts_out = hisepq.pair cx %ctrls, %tgts : vector<4x!qco.qubit>
        ```
    }];

  // FIXME: rename ctrls and tgts. Misleading for things like iSWAP.
  let arguments = (ins HiSEPQ_PairGateAttr:$gate, // FIXME: should probably be $gate_kind
                       HiSEPQ_QubitVector:$ctrls_in,
                       HiSEPQ_QubitVector:$tgts_in);
  let results = (outs HiSEPQ_QubitVector:$ctrls_out,
                      HiSEPQ_QubitVector:$tgts_out);

  let assemblyFormat = [{
        `` $gate $ctrls_in `,` $tgts_in attr-dict `:` type($ctrls_in)
    }];
}

def MzOp : HiSEPQOp<"mz", [AllTypesMatch<["qubits_in", "qubits_out"]>,
                           AllShapesMatch<["qubits_in", "bits"]>]> {
  let summary = "Measure a vector of qubits in the computational basis.";
  let description = [{
        Measures every element of `qubits_in` in the computational (Z) basis, collapsing their state,
        and yields the measured qubits plus one classical bit per element.

        The qubits come back so that the SSA chain continues past the measurement. They carry the
        collapsed post-measurement state, matching the bit each one produced; this is not a reset,
        so reusing them as fresh ancillas needs an explicit one.

        The ISA encodes measurement as a SINGLE-class instruction (`QV_MZ_FUNCT7`). We do not follow
        it there: measurement is not unitary, and folding it into `hisepq.single` would make every
        later question of the form "is this operation unitary?" answerable only by inspecting the
        gate attribute.

        Example:
        ```mlir
        %qs_out, %r = hisepq.mz %qs : vector<4x!qco.qubit> -> vector<4xi1>
        ```
    }];

  let arguments = (ins HiSEPQ_QubitVector:$qubits_in);
  let results = (outs HiSEPQ_QubitVector:$qubits_out,
                      HiSEPQ_BitVector:$bits);

  let assemblyFormat = [{
        $qubits_in attr-dict `:` type($qubits_in) `->` type($bits)
    }];
}

#endif // INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQOPS_TD_
