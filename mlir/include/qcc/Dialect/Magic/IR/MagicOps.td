// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_MAGIC_IR_MAGICOPS_TD_
#define INCLUDE_QCC_DIALECT_MAGIC_IR_MAGICOPS_TD_

include "qcc/Dialect/Magic/IR/MagicDialect.td"
include "qcc/Dialect/Magic/IR/MagicTypes.td"

include "mlir/IR/CommonAttrConstraints.td"
include "mlir/IR/OpBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// Magic traits
//===----------------------------------------------------------------------===//

// Chain values are affine: every chain operand of the op must not be used anywhere else. See the dialect
// description. Implemented in `Magic.h`.
def Magic_AffineChainOperands : NativeOpTrait<"AffineChainOperands"> {
  let cppNamespace = "::qcc::magic";
}

//===----------------------------------------------------------------------===//
// Magic operations
//===----------------------------------------------------------------------===//

// All ops are free of memory effects, but deliberately not `Pure`: the chain values are affine, so folding or
// hoisting must never duplicate them.
class Magic_Op<string mnemonic, list<Trait> traits = []>
    : Op<MagicDialect, mnemonic, !listconcat(traits, [NoMemoryEffect, Magic_AffineChainOperands])>;

// An op that transforms one chain in place: the chain type does not change.
class Magic_SameChainOp<string mnemonic, list<Trait> traits = []>
    : Magic_Op<mnemonic, !listconcat(traits, [AllTypesMatch<["chain_in", "chain_out"]>])> {
  let results = (outs Magic_IonChainType:$chain_out);
}

// A single-ion gate: the same gate applied to the ions in `ions` (ids, not positions) of one chain.
class Magic_SingleIonGateOp<string mnemonic, list<Trait> traits = []> : Magic_SameChainOp<mnemonic, traits> {
  let assemblyFormat = [{
        $chain_in custom<IonList>($ions) attr-dict `:` type($chain_in)
    }];
  let hasVerifier = 1;
}

def Magic_InitOp : Magic_Op<"init"> {
  let summary = "creates the initial chain values";
  let description = [{
        Creates the chain value of every trap at program start. There is one result per trap; all ions are active.
        Ion ids are distinct across all results, trap ids are distinct.

        Whether the chains agree with the device (occupancies, capacities, identity placement) can be checked by the
        verification pass, not here.

        Example:
        ```mlir
        // Creates two traps with 2 and 1 ions respectively.
        %t0, %t1 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1]>
        ```
    }];

  let results = (outs Variadic<Magic_IonChainType>:$chains);

  let assemblyFormat = [{
        attr-dict `:` type($chains)
    }];
  let hasVerifier = 1;
}

def Magic_ZxzOp : Magic_SingleIonGateOp<"zxz"> {
  let summary = "general single-ion rotation Rz(z2)·Rx(x)·Rz(z1) (not native)";
  let description = [{
        Applies `Rz(z2[k])·Rx(x[k])·Rz(z1[k])` to ion `ions[k]`, `z1` first.

        Example:
        ```mlir
        %c1 = magic.zxz %c0 ions [0, 2] {z1 = [0.0, 1.5708], x = [3.1416, 1.5708], z2 = [0.0, -1.5708]} : !chain
        ```
    }];

  let arguments = (ins Magic_IonChainType:$chain_in,
                       DenseI64ArrayAttr:$ions,
                       F64ArrayAttr:$z1,
                       F64ArrayAttr:$x,
                       F64ArrayAttr:$z2);
}

def Magic_RzOp : Magic_SingleIonGateOp<"rz"> {
  let summary = "Z rotation on single ions";
  let description = [{
        Applies `Rz(angles[k])` to ion `ions[k]`. Native, with zero duration.

        Example:
        ```mlir
        %c1 = magic.rz %c0 ions [1] {angles = [0.7854]} : !chain
        ```
    }];

  let arguments = (ins Magic_IonChainType:$chain_in,
                       DenseI64ArrayAttr:$ions,
                       F64ArrayAttr:$angles);
}

def Magic_SymZxzOp : Magic_SingleIonGateOp<"sym_zxz"> {
  let summary = "symmetric single-ion rotation Rz(-z)·Rx(x)·Rz(z)";
  let description = [{
        Applies `Rz(-z[k])·Rx(x[k])·Rz(z[k])` to ion `ions[k]`. Native, with zero duration.

        Example:
        ```mlir
        %c1 = magic.sym_zxz %c0 ions [0, 2] {z = [1.5708, 0.0], x = [1.5708, 3.1416]} : !chain
        ```
    }];

  let arguments = (ins Magic_IonChainType:$chain_in,
                       DenseI64ArrayAttr:$ions,
                       F64ArrayAttr:$z,
                       F64ArrayAttr:$x);
}

def Magic_ActiveZzOp : Magic_SameChainOp<"active_zz"> {
  let summary = "ZZ interaction between the active ions of a chain (intermediate)";
  let description = [{
        Applies `exp(-i/4 Σ_{i≠j} A_ij Z_i Z_j)` over the *active* ions of the chain in position order, where `A` is
        `angles`, a `k x k` matrix for `k` active ions, symmetric with zero diagonal. `rzz(θ)` between the active ions
        at active-positions `i` and `j` is `A_ij = A_ji = θ`.

        Not native: its physical realization through `delay`s depends on the coupling (J) matrix of the device.

        Example (two active ions):
        ```mlir
        %c1 = magic.active_zz %c0 {angles = dense<[[0.0, 1.5708], [1.5708, 0.0]]> : tensor<2x2xf64>} : !chain
        ```
    }];

  let arguments = (ins Magic_IonChainType:$chain_in,
                       F64ElementsAttr:$angles);

  let assemblyFormat = [{
        $chain_in attr-dict `:` type($chain_in)
    }];
  let hasVerifier = 1;
}

def Magic_DelayOp : Magic_SameChainOp<"delay"> {
  let summary = "lets the permanent coupling act between the active ions for a while";
  let description = [{
        Waits `ticks` times the device's time unit. During that time the ZZ coupling acts between all active ions of
        the chain, with strengths given by the device's coupling matrix (J) for the ions present in the trap. Native.

        Example:
        ```mlir
        %c1 = magic.delay %c0 {ticks = 2491} : !chain
        ```
    }];

  let arguments = (ins Magic_IonChainType:$chain_in,
                       ConfinedAttr<I64Attr, [IntNonNegative]>:$ticks);

  let assemblyFormat = [{
        $chain_in attr-dict `:` type($chain_in)
    }];
}

def Magic_RecodeOp : Magic_Op<"recode"> {
  let summary = "toggles ions between active and inactive";
  let description = [{
        Toggles the activation of one or more ions of the chain. Which ions follows from the types: operand and result
        hold the same ions in the same order and differ in at least one activation. Native, with zero duration.

        Example (ion 0 becomes active):
        ```mlir
        %c1 = magic.recode %c0 : !magic.ion_chain<0, [2:1, 3:1, 0:0]> -> !magic.ion_chain<0, [2:1, 3:1, 0:1]>
        ```
    }];

  let arguments = (ins Magic_IonChainType:$chain_in);
  let results = (outs Magic_IonChainType:$chain_out);

  let assemblyFormat = [{
        $chain_in attr-dict `:` type($chain_in) `->` type($chain_out)
    }];
  let hasVerifier = 1;
}

def Magic_ShuttleOp : Magic_Op<"shuttle"> {
  let summary = "moves one ion from one trap to the front of another";
  let description = [{
        Moves exactly one ion out of `from` and inserts it at the front of `to`, activation kept, everything else
        unchanged. The two chains belong to different traps. Native, with zero duration; a sync point for the timing.

        Which ion moves follows from the types. The op verifier accepts any position in `from`; that the machine can
        only shuttle the *front* ion is a device rule checked by the final verification pass.

        Example:
        ```mlir
        %f1, %t1 = magic.shuttle %f0, %t0 : !magic.ion_chain<0, [2:1, 3:1, 0:0]>, !magic.ion_chain<1, [1:1]>
                                         -> !magic.ion_chain<0, [3:1, 0:0]>, !magic.ion_chain<1, [2:1, 1:1]>
        ```
    }];

  let arguments = (ins Magic_IonChainType:$from_in,
                       Magic_IonChainType:$to_in);
  let results = (outs Magic_IonChainType:$from_out,
                      Magic_IonChainType:$to_out);

  let assemblyFormat = [{
        $from_in `,` $to_in attr-dict `:` type($from_in) `,` type($to_in) `->` type($from_out) `,` type($to_out)
    }];
  let hasVerifier = 1;

  let extraClassDeclaration = [{
        /// The id of the ion that moves.
        int64_t getMovedIon() { return getToOut().getType().getSlots().front().ion; }
    }];
}

def Magic_MzdOp : Magic_Op<"mzd"> {
  let summary = "destructively measures every ion of a chain";
  let description = [{
        Measures all ions of the chain in the computational basis and yields one `i1` per ion, in position order. The
        chain is consumed: measurement happens at the very end of a program. Native.

        Example:
        ```mlir
        %m2, %m3, %m0 = magic.mzd %c : !magic.ion_chain<0, [2:1, 3:1, 0:0]> -> i1, i1, i1
        ```
    }];

  let arguments = (ins Magic_IonChainType:$chain);
  let results = (outs Variadic<I1>:$bits);

  let assemblyFormat = [{
        $chain attr-dict `:` type($chain) `->` type($bits)
    }];
  let hasVerifier = 1;
}

def Magic_InterTrapZzOp : Magic_Op<"inter_trap_zz", [AllTypesMatch<["a_in", "a_out"]>,
                                                     AllTypesMatch<["b_in", "b_out"]>]> {
  let summary = "rzz between two ions in different traps (intermediate)";
  let description = [{
        Applies `rzz(angle) = exp(-i angle/2 Z⊗Z)` between ion `ions[0]` of chain `a` and ion `ions[1]` of chain `b`,
        which belong to different traps. Not native: its lowering shuttles one of the ions over, so it is a sync point
        in the making.

        Example:
        ```mlir
        %a1, %b1 = magic.inter_trap_zz %a0, %b0 ions [1, 2] {angle = 1.5708} : !chain_a, !chain_b
        ```
    }];

  let arguments = (ins Magic_IonChainType:$a_in,
                       Magic_IonChainType:$b_in,
                       DenseI64ArrayAttr:$ions,
                       F64Attr:$angle);
  let results = (outs Magic_IonChainType:$a_out,
                      Magic_IonChainType:$b_out);

  let assemblyFormat = [{
        $a_in `,` $b_in custom<IonList>($ions) attr-dict `:` type($a_in) `,` type($b_in)
    }];
  let hasVerifier = 1;
}

def Magic_SwapOp : Magic_SameChainOp<"swap"> {
  let summary = "logical swap of two ions of a chain (intermediate)";
  let description = [{
        Swaps the quantum states of the two ions `ions[0]` and `ions[1]` of the chain. Not native: it is compiled into
        three `active_zz` with single-ion layers in between. The chain type is unchanged; the ions keep their ids and
        positions.

        Example:
        ```mlir
        %c1 = magic.swap %c0 ions [4, 0] : !chain
        ```
    }];

  let arguments = (ins Magic_IonChainType:$chain_in,
                       DenseI64ArrayAttr:$ions);

  let assemblyFormat = [{
        $chain_in custom<IonList>($ions) attr-dict `:` type($chain_in)
    }];
  let hasVerifier = 1;
}

#endif // INCLUDE_QCC_DIALECT_MAGIC_IR_MAGICOPS_TD_
