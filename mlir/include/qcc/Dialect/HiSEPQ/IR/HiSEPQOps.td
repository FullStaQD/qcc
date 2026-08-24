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

// Every operation here reads and writes quantum state, which keeps it from being folded away and
// keeps the operations ordered with respect to each other.
//
// FIXME: This is stricter than the hardware. Gates on disjoint lanes commute, so once lane sets are
// known statically we can attach per-qubit resources instead and let independent instructions
// reorder.
class HiSEPQOp<string mnemonic, list<Trait> traits = []>
    : Op<HiSEPQDialect, mnemonic,
         !listconcat(traits, [MemoryEffects<[MemRead, MemWrite]>])>;

def SingleOp : HiSEPQOp<"single"> {
  let summary = "Apply one single-qubit gate across a vector of qubits.";
  let description = [{
        Applies `gate` to every active lane of `qubits`, in place. This is one `QV.SINGLE`
        instruction: the gate kind occupies the instruction's `GateID` field and the qubit indices
        live in the vector register named by `vs1`.

        FIXME: should be "canonicalized"
        The lanes of one operation must be distinct qubits. Because they are distinct and carry the
        same gate, they commute, which is what makes lane order a free choice; the canonical form
        sorts lanes ascending by qubit index.

        `mask` is optional and selects the active lanes; absent, every lane is active. A masked-off
        lane is left untouched. Note that the ISA has no mask field at all -- only `vl`, which
        activates a prefix of the lanes -- so masks exist here precisely so that lane selection
        survives until a pass can turn it into `vl`, into a permutation, or into several
        instructions.

        Example:
        ```mlir
        hisepq.single h %qs : vector<4x!qc.qubit>
        hisepq.single x %qs mask %m : vector<4x!qc.qubit>, vector<4xi1>
        ```
    }];

  let arguments = (ins HiSEPQ_SingleGateAttr:$gate,
                       HiSEPQ_QubitVector:$qubits,
                       Optional<HiSEPQ_MaskVector>:$mask);
  let results = (outs);

  let assemblyFormat = [{
        `` $gate $qubits (`mask` $mask^)? attr-dict `:` type($qubits) (`,` type($mask)^)?
    }];

  let hasVerifier = 1;
}

def PairOp : HiSEPQOp<"pair", [AllTypesMatch<["ctrls", "tgts"]>]> {
  let summary = "Apply one two-qubit gate across two vectors of qubits.";
  let description = [{
        Applies `gate` to every active lane, in place. Lane `i` of `ctrls` and lane `i` of `tgts`
        are the control and the target of the same gate, so the two vectors necessarily have the
        same length.

        This is one `QV.PAIR` instruction. Beware that the encoding orders the registers the other
        way round -- `vs1` holds the targets and `vs2` the sources/controls -- so a lowering has to
        swap. We keep control-before-target here because that is how the gates read.

        All 2N qubits named by one operation must be distinct. The canonical form sorts lanes
        ascending by control index, carrying each lane's target along with it.

        `mask` is optional and selects the active lanes; see `hisepq.single` for what that means and
        why it is not part of the encoding.

        Example:
        ```mlir
        hisepq.pair cx %ctrls, %tgts : vector<4x!qc.qubit>
        ```
    }];

  let arguments = (ins HiSEPQ_PairGateAttr:$gate,
                       HiSEPQ_QubitVector:$ctrls,
                       HiSEPQ_QubitVector:$tgts,
                       Optional<HiSEPQ_MaskVector>:$mask);
  let results = (outs);

  let assemblyFormat = [{
        `` $gate $ctrls `,` $tgts (`mask` $mask^)? attr-dict `:` type($ctrls) (`,` type($mask)^)?
    }];

  let hasVerifier = 1;
}

def MzOp : HiSEPQOp<"mz", [AllShapesMatch<["qubits", "result"]>]> {
  let summary = "Measure a vector of qubits in the computational basis.";
  let description = [{
        Measures every active lane of `qubits` in the computational (Z) basis, collapsing their
        state, and yields one classical bit per lane. The bit for a masked-off lane is undefined.

        The ISA encodes measurement as a SINGLE-class instruction (`QV_MZ_FUNCT7`). We do not follow
        it there: measurement is not unitary, and folding it into `hisepq.single` would make every
        later question of the form "is this operation unitary?" answerable only by inspecting the
        gate attribute.

        Example:
        ```mlir
        %r = hisepq.mz %qs : vector<4x!qc.qubit> -> vector<4xi1>
        ```
    }];

  let arguments = (ins HiSEPQ_QubitVector:$qubits,
                       Optional<HiSEPQ_MaskVector>:$mask);
  let results = (outs HiSEPQ_MaskVector:$result);

  let assemblyFormat = [{
        $qubits (`mask` $mask^)? attr-dict `:` type($qubits) (`,` type($mask)^)? `->` type($result)
    }];

  let hasVerifier = 1;
}

#endif // INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQOPS_TD_
