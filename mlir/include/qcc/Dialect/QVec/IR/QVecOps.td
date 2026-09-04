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
class QVecOp<string mnemonic, list<Trait> traits = []>
    : Op<QVecDialect, mnemonic,
         !listconcat(traits, [MemoryEffects<[MemRead, MemWrite]>, QVec_QubitSlotOpInterface])>;

def SingleOp : QVecOp<"single", [AllTypesMatch<["qubits_in", "qubits_out"]>]> {
  let summary = "single-qubit gate across a vector of qubits";
  let description = [{
        A `single` applies the same gate over all qubits referenced in its operand vector. Each element of the vector
        must be distinct, consistent with the linearly typed qubit type.

        Example:
        ```mlir
        %qs_out = qvec.single h %qs : vector<4x!qco.qubit>
        ```
    }];

  let arguments = (ins QVec_SingleGateAttr:$gate_kind,
                       QVec_QubitVector:$qubits_in);
  let results = (outs QVec_QubitVector:$qubits_out);

  let assemblyFormat = [{
        $gate_kind $qubits_in attr-dict `:` type($qubits_in)
    }];

  let extraClassDeclaration = [{
        /// The gate acts on one qubit, hence one slot.
        unsigned getNumQubitSlots() { return 1; }

        ::mlir::TypedValue<::mlir::VectorType> getQubitOperand(unsigned slot) {
          assert(slot == 0 && "no such qubit slot");
          return getQubitsIn();
        }

        ::mlir::TypedValue<::mlir::VectorType> getQubitResult(unsigned slot) {
          assert(slot == 0 && "no such qubit slot");
          return getQubitsOut();
        }
    }];
}

def PairOp : QVecOp<"pair", [AllTypesMatch<["lhs_in", "rhs_in", "lhs_out", "rhs_out"]>]> {
  let summary = "two-qubit gate across two vectors of qubits";
  let description = [{
        Applies a two-qubit gate to each pair of qubits `lhs[i]` and `rhs[i]`. All qubits must be distinct, consistent
        with a linearly typed qubit.

        Example:
        ```mlir
        %cs_out, %ts_out = qvec.pair cx %ctrls, %tgts : vector<4x!qco.qubit>
        ```
    }];

  let arguments = (ins QVec_PairGateAttr:$gate_kind,
                       QVec_QubitVector:$lhs_in,
                       QVec_QubitVector:$rhs_in);
  let results = (outs QVec_QubitVector:$lhs_out,
                      QVec_QubitVector:$rhs_out);

  let assemblyFormat = [{
        $gate_kind $lhs_in `,` $rhs_in attr-dict `:` type($lhs_in)
    }];

  let extraClassDeclaration = [{
        /// The gate acts on two qubits: slot 0 is the left operand, slot 1 the right one.
        unsigned getNumQubitSlots() { return 2; }

        ::mlir::TypedValue<::mlir::VectorType> getQubitOperand(unsigned slot) {
          assert(slot < 2 && "no such qubit slot");
          return slot == 0 ? getLhsIn() : getRhsIn();
        }

        ::mlir::TypedValue<::mlir::VectorType> getQubitResult(unsigned slot) {
          assert(slot < 2 && "no such qubit slot");
          return slot == 0 ? getLhsOut() : getRhsOut();
        }
    }];
}

def MzOp : QVecOp<"mz", [AllTypesMatch<["qubits_in", "qubits_out"]>,
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
        /// One slot for the measured qubits. `bits` is classical and hence outside the slots.
        unsigned getNumQubitSlots() { return 1; }

        ::mlir::TypedValue<::mlir::VectorType> getQubitOperand(unsigned slot) {
          assert(slot == 0 && "no such qubit slot");
          return getQubitsIn();
        }

        ::mlir::TypedValue<::mlir::VectorType> getQubitResult(unsigned slot) {
          assert(slot == 0 && "no such qubit slot");
          return getQubitsOut();
        }
    }];
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECOPS_TD_
