// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPOPS_TD_
#define INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPOPS_TD_

include "mlir/IR/OpBase.td"
include "mlir/IR/BuiltinTypes.td"
include "PrelimHLEPDialect.td"
include "PrelimHLEPTypes.td"
include "PrelimHLEPAttrs.td"
include "PrelimHLEPEffects.td"


//===----------------------------------------------------------------------===//
// PrelimHLEP traits
//===----------------------------------------------------------------------===//

// The op must be nested (directly or indirectly) within a `prelimhlep.halo`-attributed function.
def PrelimHLEP_InHaloedFunction : NativeOpTrait<"InHaloedFunction"> {
  let cppNamespace = "::qcc::prelimhlep";
}

//===----------------------------------------------------------------------===//
// PrelimHLEP operations
//
// Side effects follow PrelimHLEPEffects.td: ops with a single world that
// neither create nor destroy linear values are `Pure`; `lin` computes its
// effects from its body.
//===----------------------------------------------------------------------===//

class PrelimHLEPOp<string mnemonic, list<Trait> traits = []> :
        Op<PrelimHLEPDialect, mnemonic, traits>;

def AddPhaseOp : PrelimHLEPOp<"add_phase", [Pure, PrelimHLEP_InHaloedFunction]> {
    let summary = "Scales the linear fibres of a value by exp(i*alpha), a purely imaginary exponent.";
    let description = [{
        Within `LinearHalo`-attributed functions, homogeneously multiplies
        every fibre of a value by `exp(i * alpha)` for real `alpha`.

        Example:
        ```
        prelimhlep.add_phase %alpha, %t : (f64, T) -> T
        ```

        The verifier checks that the
        operand and result types match.

        TODO: consider allowing other types for angles.
    }];

    let arguments = (ins F64:$alpha, AnyType:$input);
    let results = (outs AnyType:$result);

    let assemblyFormat = "$alpha `,` $input attr-dict `:` `(` type($alpha) `,` type($input) `)` `->` type($result)";
    let hasVerifier = 1;
}

def LinOp : PrelimHLEPOp<"lin", [SingleBlock, RecursiveMemoryEffects, RecursivelySpeculatable,
                                  DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
                                  PrelimHLEP_InHaloedFunction]> {
    let summary = "Partial linearization of a function between product types.";
    let description = [{
        Implements partial linearization: the `delinearizedOperands`
        (of `!prelimhlep.lin<T>` type) are delinearized into region block
        arguments of type `T` (the "base type"). The region is not isolated from above, so any
        other (captured) values needed by the body are simply
        referenced directly from the enclosing scope, without being listed
        as explicit operands. The region body computes the results, which
        are `prelimhlep.output`-ed and re-linearized on exit.

        Example:
        ```
        %out_lin, %out_auxiliary = prelimhlep.lin (
            %in_delinearized : i1 from %in_lin : !prelimhlep.lin<i1>, ...
        ) -> (!prelimhlep.lin<i1>, i1, ...) {
            %out_delinearized, %out_aux =
                some.op (%in_delinearized, %in_capture) : (i1, i1) -> (i1, i1)
            prelimhlep.output (%out_delinearized : i1) carrying (%out_aux : i1)
        }
        ```
        Each binding's block argument type and the base type of its
        source operand's `!prelimhlep.lin<...>` type are independently
        parsed and are related by `LinOp`'s verifier.

        The verifier checks that the
        block's argument types match the `delinearizedOperands` base
        types, and that the op's result types are the re-linearization of
        the `prelimhlep.output` terminator's delinearized results, followed
        by its auxiliary results unchanged.

        In the example above this means the verifier type-checks:
        - `%in_delinearized` is of type `i1` (the base type of
          `%in_lin`'s `!prelimhlep.lin<i1>` type),
        - `%out_delinearized` is of type `i1` (the base type of
          `%out_lin`'s `!prelimhlep.lin<i1>` type),
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

def OutputOp : PrelimHLEPOp<"output", [Pure, Terminator, AttrSizedOperandSegments, HasParent<"LinOp">]> {
    let summary = "Terminates the body region of a `prelimhlep.lin` op.";
    let description = [{
        Yields the (still delinearized) results of a `prelimhlep.lin`
        region, which are re-linearized on exit, plus any purely classical
        auxiliary results (e.g. measurement outcomes) that are not
        linearized.

        Example:
        ```
        prelimhlep.output (%out_delinearized : T, ...) carrying (%out_aux : T, ...)
        ```
    }];

    let arguments = (ins Variadic<AnyType>:$delinearizedResults,
                          Variadic<AnyType>:$auxiliaryResults);
    let hasCustomAssemblyFormat = 1;
}

def ExpOp : PrelimHLEPOp<"exp", [Pure, PrelimHLEP_InHaloedFunction]> {
    let summary = "Exponential map: applies exp(-i * angle * hamiltonian) to a purely quantum value.";
    let description = [{
        Obtains a unitary operator from a Lie algebra element (given as a
        `prelimhlep.hamiltonian` attribute, a Pauli-product-basis element of
        u(2^n)) and a real angle, and applies it. Only available for purely
        quantum types (i.e. `!prelimhlep.lin<i<n>>`).

        Example:
        ```
        %out_state = prelimhlep.exp %param hamiltonian<1, X[0] + Y[0]> %in_state :
            (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
        ```

        The verifier checks that the hamiltonian's qubit count matches the
        operand/result type's bit width, and that operand and result types
        match and are purely-quantum `!prelimhlep.lin<i<n>>` types.

        TODO: double-check the sign convention for the exponent
        TODO: consider allowing other types for angles.
        TODO: consider allowing other types for input and result (e.g. `!prelimhlep.lin<!prelimhlep.x<n>>`).
    }];

    let arguments = (ins F64:$angle, HamiltonianAttr:$hamiltonian, AnyType:$input);
    let results = (outs AnyType:$result);

    let assemblyFormat = "$angle `hamiltonian` $hamiltonian $input attr-dict `:` `(` type($angle) `,` type($input) `)` `->` type($result)";
    let hasVerifier = 1;
}

def BaseChangeOp : PrelimHLEPOp<"base_change", [Pure, PrelimHLEP_InHaloedFunction]> {
    let summary = "Distinguished isomorphism between the Z-, X-, and Y-basis linearizations of the same space.";
    let description = [{
        Converts between `!prelimhlep.lin<i<n>>`, `!prelimhlep.lin<!prelimhlep.x<n>>`,
        and `!prelimhlep.lin<!prelimhlep.y<n>>`, which are the same vector
        space equipped with different distinguished bases.

        Example:
        ```
        %qubit_in_x_basis = prelimhlep.base_change %qubit_in_z_basis :
            !prelimhlep.lin<i1> -> !prelimhlep.lin<!prelimhlep.x<1>>
        ```

        The verifier checks that operand and result types are `!prelimhlep.lin<...>` over `i<n>`/`x<n>`/
        `y<n>` of matching `n`.
    }];

    let arguments = (ins AnyType:$input);
    let results = (outs AnyType:$result);

    let assemblyFormat = "$input attr-dict `:` type($input) `->` type($result)";
    let hasVerifier = 1;
}

def ConstantOp : PrelimHLEPOp<"constant", [Pure, ConstantLike]> {
    let summary = "A classical literal of X- or Y-basis type.";
    let description = [{
        Constructs a classical constant of `!prelimhlep.x<n>` or
        `!prelimhlep.y<n>` from a string of basis symbols (`+`/`-` for X,
        `->`/`<-` for Y). This is the X-/Y-basis analogue of
        `arith.constant` for `i<n>`: a qubit register in a basis state is
        obtained by linearizing the constant with `prelimhlep.lin`.

        Example:
        ```
        %xxx = prelimhlep.constant "++-" : !prelimhlep.x<3>
        %yyy = prelimhlep.constant "-><-->" : !prelimhlep.y<3>
        %plus = prelimhlep.lin () -> (!prelimhlep.lin<!prelimhlep.x<1>>) {
            %p = prelimhlep.constant "+" : !prelimhlep.x<1>
            prelimhlep.output (%p : !prelimhlep.x<1>)
        }
        ```

        The verifier checks that `value` consists only of valid basis
        symbols for the result type (`+`/`-` for X, `->`/`<-` for Y), with
        `n` symbols for a result type of size `n`.

        Being classical, the op is `Pure`: allocating the linear value is
        the job of the enclosing `prelimhlep.lin` (see its side effects).

        TODO: consider defining a custom attribute instead of a string.
    }];

    let arguments = (ins StrAttr:$value);
    let results = (outs AnyTypeOf<[XType, YType]>:$result);

    let assemblyFormat = "$value attr-dict `:` type($result)";
    let hasFolder = 1;
    let hasVerifier = 1;
}

def UnitValueOp : PrelimHLEPOp<"unit_value", [Pure]> {
    let summary = "Constructs the unique value of !prelimhlep.unit.";
    let description = [{
        Creates a `!prelimhlep.unit` value.

        Example:
        ```
        %phase = prelimhlep.unit_value : !prelimhlep.unit
        ```
    }];

    let arguments = (ins);
    let results = (outs UnitType:$result);

    let assemblyFormat = "attr-dict `:` type($result)";
}

#endif // INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPOPS_TD_
