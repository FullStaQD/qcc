// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_HLEP_IR_HLEPOPS_TD_
#define INCLUDE_QCC_DIALECT_HLEP_IR_HLEPOPS_TD_

include "mlir/IR/OpBase.td"
include "mlir/IR/BuiltinTypes.td"
include "HLEPDialect.td"
include "HLEPTypes.td"
include "HLEPAttrs.td"
include "HLEPEffects.td"
include "HLEPInterfaces.td"


//===----------------------------------------------------------------------===//
// HLEP traits
//===----------------------------------------------------------------------===//

// The op must be nested (directly or indirectly) within a `hlep.halo`-attributed function.
def HLEP_InHaloedFunction : NativeOpTrait<"InHaloedFunction"> {
  let cppNamespace = "::qcc::hlep";
}

//===----------------------------------------------------------------------===//
// HLEP operations
//
// Side effects follow HLEPEffects.td: ops with a single world that
// neither create nor destroy linear values are `Pure`, except `add_phase`,
// which writes the quantum state; `lin` computes its effects from its body.
//===----------------------------------------------------------------------===//

// Every op of this dialect is linearity-aware: its own verifier is responsible
// for how it handles values subject to linearity.
class HLEPOp<string mnemonic, list<Trait> traits = []> :
        Op<HLEPDialect, mnemonic, !listconcat(traits, [HLEP_LinearityAwareOpInterface])>;

def AddPhaseOp : HLEPOp<"add_phase", [MemoryEffects<[MemWrite<HLEP_QuantumStateResource>]>,
                                              HLEP_InHaloedFunction]> {
    let summary = "Scales the linear fibres of a value by exp(i*alpha), a purely imaginary exponent.";
    let description = [{
        Within `LinearHalo`-attributed functions, homogeneously multiplies
        every fibre of a value by `exp(i * alpha)` for real `alpha`.

        Example:
        ```
        hlep.add_phase %alpha, %t : (f64, T) -> T
        ```

        The verifier checks that the
        operand and result types match.

        The op is not `Pure`: its result carries the same value as its
        input, and the phase lives in the quantum state, which the op writes.
        Otherwise two phases on the same (delinearized, hence non-linear)
        value would be merged by CSE, and a phase whose result is unused
        would be erased as dead.

        TODO: consider allowing other types for angles.
    }];

    let arguments = (ins F64:$alpha, AnyType:$input);
    let results = (outs AnyType:$result);

    let assemblyFormat = "$alpha `,` $input attr-dict `:` `(` type($alpha) `,` type($input) `)` `->` type($result)";
    let hasVerifier = 1;
}

def LinOp : HLEPOp<"lin", [SingleBlock, RecursiveMemoryEffects, RecursivelySpeculatable,
                                  DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
                                  HLEP_InHaloedFunction]> {
    let summary = "Partial linearization of a function between product types.";
    let description = [{
        Implements partial linearization: the `delinearizedOperands`
        (of `!hlep.lin<T>` type) are delinearized into region block
        arguments of type `T` (the "base type"). The region is not isolated from above, so any
        other (captured) values needed by the body are simply
        referenced directly from the enclosing scope, without being listed
        as explicit operands. The region body computes the results, which
        are `hlep.output`-ed and re-linearized on exit.

        Example:
        ```
        %out_lin, %out_auxiliary = hlep.lin (
            %in_delinearized : i1 from %in_lin : !hlep.lin<i1>, ...
        ) -> (!hlep.lin<i1>, i1, ...) {
            %out_delinearized, %out_aux =
                some.op (%in_delinearized, %in_capture) : (i1, i1) -> (i1, i1)
            hlep.output (%out_delinearized : i1) carrying (%out_aux : i1)
        }
        ```
        Each binding's block argument type and the base type of its
        source operand's `!hlep.lin<...>` type are independently
        parsed and are related by `LinOp`'s verifier.

        The verifier checks that the
        block's argument types match the `delinearizedOperands` base
        types, and that the op's result types are the re-linearization of
        the `hlep.output` terminator's delinearized results, followed
        by its auxiliary results unchanged.

        In the example above this means the verifier type-checks:
        - `%in_delinearized` is of type `i1` (the base type of
          `%in_lin`'s `!hlep.lin<i1>` type),
        - `%out_delinearized` is of type `i1` (the base type of
          `%out_lin`'s `!hlep.lin<i1>` type),
        - `%out_aux` is of type `i1` (the same as `%out_auxiliary`'s type).

        Side effects are computed from the op: the effects of the body, plus
        - a read and a write of the world resource if a classical
          `carrying` result may depend on a delinearized value (the op involves
          a measurement),
        - an allocation of the linear results if the op consumes no linear
          value (neither delinearized nor captured), and
        - a free of the consumed linear values if the op has no linear
          results.
        Otherwise, e.g. for an X gate, the op is `Pure`.

        TODO: The side effects are preliminary and need to be better understood.
    }];

    let arguments = (ins Variadic<LinType>:$delinearizedOperands);
    let results = (outs Variadic<AnyType>:$results);
    let regions = (region SizedRegion<1>:$body);
    let hasVerifier = 1;
    let hasCustomAssemblyFormat = 1;
}

def OutputOp : HLEPOp<"output", [Pure, Terminator, AttrSizedOperandSegments, HasParent<"LinOp">]> {
    let summary = "Terminates the body region of a `hlep.lin` op.";
    let description = [{
        Yields the (still delinearized) results of a `hlep.lin`
        region, which are re-linearized on exit, plus any purely classical
        auxiliary results (e.g. measurement outcomes) that are not
        linearized.

        Example:
        ```
        hlep.output (%out_delinearized : T, ...) carrying (%out_aux : T, ...)
        ```
    }];

    let arguments = (ins Variadic<AnyType>:$delinearizedResults,
                          Variadic<AnyType>:$auxiliaryResults);
    let hasCustomAssemblyFormat = 1;
}

def ExpOp : HLEPOp<"exp", [Pure, HLEP_InHaloedFunction]> {
    let summary = "Exponential map: applies exp(-i * angle * hamiltonian) to a purely quantum value.";
    let description = [{
        Obtains a unitary operator from a Lie algebra element (given as a
        `hlep.hamiltonian` attribute, a Pauli-product-basis element of
        u(2^n)) and a real angle, and applies it. Only available for purely
        quantum types (i.e. `!hlep.lin<i<n>>`).

        Example:
        ```
        %out_state = hlep.exp %param hamiltonian<1, X[0] + Y[0]> %in_state :
            (f64, !hlep.lin<i1>) -> !hlep.lin<i1>
        ```

        The verifier checks that the hamiltonian's qubit count matches the
        operand/result type's bit width, and that operand and result types
        match and are purely-quantum `!hlep.lin<i<n>>` types.

        TODO: double-check the sign convention for the exponent
        TODO: consider allowing other types for angles.
        TODO: consider allowing other types for input and result (e.g. `!hlep.lin<!hlep.x<n>>`).
    }];

    let arguments = (ins F64:$angle, HamiltonianAttr:$hamiltonian, AnyType:$input);
    let results = (outs AnyType:$result);

    let assemblyFormat = "$angle `hamiltonian` $hamiltonian $input attr-dict `:` `(` type($angle) `,` type($input) `)` `->` type($result)";
    let hasVerifier = 1;
}

def BaseChangeOp : HLEPOp<"base_change", [Pure, HLEP_InHaloedFunction]> {
    let summary = "Distinguished isomorphism between the Z-, X-, and Y-basis linearizations of the same space.";
    let description = [{
        Converts between `!hlep.lin<i<n>>`, `!hlep.lin<!hlep.x<n>>`,
        and `!hlep.lin<!hlep.y<n>>`, which are the same vector
        space equipped with different distinguished bases.

        Example:
        ```
        %qubit_in_x_basis = hlep.base_change %qubit_in_z_basis :
            !hlep.lin<i1> -> !hlep.lin<!hlep.x<1>>
        ```

        The verifier checks that operand and result types are `!hlep.lin<...>` over `i<n>`/`x<n>`/
        `y<n>` of matching `n`.
    }];

    let arguments = (ins AnyType:$input);
    let results = (outs AnyType:$result);

    let assemblyFormat = "$input attr-dict `:` type($input) `->` type($result)";
    let hasVerifier = 1;
}

def ConstantOp : HLEPOp<"constant", [Pure, ConstantLike]> {
    let summary = "A classical literal of X- or Y-basis type.";
    let description = [{
        Constructs a classical constant of `!hlep.x<n>` or
        `!hlep.y<n>` from a string of basis symbols (`+`/`-` for X,
        `>`/`<` for Y, the tips of the arrows `->`/`<-`). This is the X-/Y-basis analogue of
        `arith.constant` for `i<n>`: a qubit register in a basis state is
        obtained by linearizing the constant with `hlep.lin`.

        Example:
        ```
        %xxx = hlep.constant "++-" : !hlep.x<3>
        %yyy = hlep.constant "><>" : !hlep.y<3>
        %plus = hlep.lin () -> (!hlep.lin<!hlep.x<1>>) {
            %p = hlep.constant "+" : !hlep.x<1>
            hlep.output (%p : !hlep.x<1>)
        }
        ```

        The verifier checks that `value` consists only of valid basis
        symbols for the result type (`+`/`-` for X, `>`/`<` for Y), with
        `n` symbols for a result type of size `n`.

        Being classical, the op is `Pure`: allocating the linear value is
        the job of the enclosing `hlep.lin` (see its side effects).

        TODO: consider defining a custom attribute instead of a string.
    }];

    let arguments = (ins StrAttr:$value);
    let results = (outs AnyTypeOf<[XType, YType]>:$result);

    let assemblyFormat = "$value attr-dict `:` type($result)";
    let hasFolder = 1;
    let hasVerifier = 1;
}

def UnitValueOp : HLEPOp<"unit_value", [Pure]> {
    let summary = "Constructs the unique value of !hlep.unit.";
    let description = [{
        Creates a `!hlep.unit` value.

        Example:
        ```
        %phase = hlep.unit_value : !hlep.unit
        ```
    }];

    let arguments = (ins);
    let results = (outs UnitType:$result);

    let assemblyFormat = "attr-dict `:` type($result)";
}

#endif // INCLUDE_QCC_DIALECT_HLEP_IR_HLEPOPS_TD_
