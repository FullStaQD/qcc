#ifndef INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPOPS_TD_
#define INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPOPS_TD_

include "mlir/IR/OpBase.td"
include "mlir/IR/BuiltinTypes.td"
include "PrelimHLEPDialect.td"
include "PrelimHLEPTypes.td"
include "PrelimHLEPAttrs.td"


//===----------------------------------------------------------------------===//
// PrelimHLEP operations
//
// See mlir/docs/Dialects/PrelimHLEP.md, section "Core Attributes and Ops"
// for the semantics these ops stub out. None of these ops have verifiers,
// canonicalization, folders, or lowerings yet -- declarations only.
//===----------------------------------------------------------------------===//

class PrelimHLEPOp<string mnemonic, list<Trait> traits = []> :
        Op<PrelimHLEPDialect, mnemonic, traits>;

def ScaleOp : PrelimHLEPOp<"scale"> {
    let summary = "Scales all fibres of a haloed value by a complex factor.";
    let description = [{
        Within `LinearHalo`-attributed functions, homogeneously scales every
        fibre of a value by a complex factor. See "Scale, AddPhase" in the
        design doc.

        **IR Realization:**
        `prelim_hlep.scale %factor, %t : (complex<f64>, T) -> T`

        The verifier checks that the op is nested (directly or indirectly)
        within a `prelim_hlep.halo`-attributed function.

        TODO: verify that operand and result types match.
        TODO: consider canonicalizing into `prelim_hlep.add_phase`.
        TODO: consider deprecating this in favor of `prelim_hlep.add_phase`.
    }];

    let arguments = (ins Complex<F64>:$factor, AnyType:$input);
    let results = (outs AnyType:$result);

    let assemblyFormat = "$factor `,` $input attr-dict `:` `(` type($factor) `,` type($input) `)` `->` type($result)";
    let hasVerifier = 1;
}

def AddPhaseOp : PrelimHLEPOp<"add_phase"> {
    let summary = "Scales a haloed value by exp(i*alpha), a purely imaginary exponent.";
    let description = [{
        Shorthand for `prelim_hlep.scale` by `exp(i * alpha)` for a real
        `alpha`. See "Scale, AddPhase" in the design doc.

        **IR Realization:**
        `prelim_hlep.add_phase %alpha, %t : (f64, T) -> T`

        The verifier checks that the op is nested (directly or indirectly)
        within a `prelim_hlep.halo`-attributed function.

        TODO: verify that operand and result types match; consider folding
        into `prelim_hlep.scale` or vice versa.
        TODO: consider allowing other types for angles.
    }];

    let arguments = (ins F64:$alpha, AnyType:$input);
    let results = (outs AnyType:$result);

    let assemblyFormat = "$alpha `,` $input attr-dict `:` `(` type($alpha) `,` type($input) `)` `->` type($result)";
    let hasVerifier = 1;
}

def LinOp : PrelimHLEPOp<"lin", [SingleBlock]> {
    let summary = "Partial linearization of a function between product types.";
    let description = [{
        Implements partial linearization (always on the left tensor
        factor(s)): the `delinearizedOperands` (of `!prelim_hlep.lin<T>`
        type) are delinearized into region block arguments of type `T`. The
        region is not isolated from above, so any other (captured) values
        needed by the body -- the right tensor factor(s) -- are simply
        referenced directly from the enclosing scope, without being listed
        as explicit operands. The region body computes the results, which
        are `prelim_hlep.output`-ed and re-linearized on exit. See
        "(Partial) Linearization" in the design doc for the full semantics,
        including the role of the measurement set M(f) and the composition
        theorem.

        **IR Realization:**
        ```mlir
        %out_lin, %out_auxiliary = prelimhlep.lin (
            %in_delinearized : i1 from %in_lin : !prelimhlep.lin<i1>, ...
        ) -> (!prelimhlep.lin<i1>, i1, ...) {
            %out_delinearized, %out_aux =
                some.op (%in_delinearized, %in_capture) : (i1, i1) -> (i1, i1)
            prelimhlep.output (%out_delinearized) carrying (%out_aux)
        }
        ```
        Each binding's block argument type and the element type of its
        source operand's `!prelim_hlep.lin<...>` type are independently
        parsed and are only related by `LinOp`'s verifier, not the grammar
        itself.

        The verifier checks that the op is nested (directly or indirectly)
        within a `prelim_hlep.halo`-attributed function; that the body
        block's argument types match the `delinearizedOperands` element
        types; and that the op's result types are the re-linearization of
        the `prelim_hlep.output` terminator's delinearized results,
        followed by its auxiliary results unchanged.
    }];

    let arguments = (ins Variadic<LinType>:$delinearizedOperands);
    let results = (outs Variadic<AnyType>:$results);
    let regions = (region SizedRegion<1>:$body);
    let hasVerifier = 1;
    let hasCustomAssemblyFormat = 1;
}

def OutputOp : PrelimHLEPOp<"output", [Terminator, AttrSizedOperandSegments, HasParent<"LinOp">]> {
    let summary = "Terminates the body region of a `prelim_hlep.lin` op.";
    let description = [{
        Yields the (still delinearized) results of a `prelim_hlep.lin`
        region, which are re-linearized on exit, plus any purely classical
        auxiliary results (e.g. measurement outcomes) that are not
        linearized. See "(Partial) Linearization" in the design doc.

        **IR Realization:**
        `prelim_hlep.output (%out_delinearized, ...) carrying (%out_aux, ...)`

        The verifier checks that the op is nested (directly or indirectly)
        within a `prelim_hlep.halo`-attributed function.

        TODO: custom assembly format matching the syntax above. (Operand
        types/count are checked against the enclosing `prelim_hlep.lin`'s
        results by `LinOp`'s verifier.)
    }];

    let arguments = (ins Variadic<AnyType>:$delinearizedResults,
                          Variadic<AnyType>:$auxiliaryResults);
    let hasVerifier = 1;
}

def ExpOp : PrelimHLEPOp<"exp"> {
    let summary = "Exponential map: applies exp(-i * angle * hamiltonian) to a purely quantum value.";
    let description = [{
        Obtains a unitary operator from a Lie algebra element (given as a
        `prelim_hlep.hamiltonian` attribute, a Pauli-product-basis element of
        u(2^n)) and a real angle, and applies it. Only available for purely
        quantum types (i.e. `!prelim_hlep.lin<i<n>>`). See "Exponential map"
        in the design doc.

        **IR Realization:**
        ```mlir
        %out_state = prelim_hlep.exp %param hamiltonian<1, X[0] + Y[0]> %in_state :
            (f64, !prelim_hlep.lin<i1>) -> !prelim_hlep.lin<i1>
        ```

        TODO: custom assembly format inlining the `hamiltonian<...>`
        attribute (rather than via the generic `attr-dict`); verifier
        checking the hamiltonian's qubit count against the operand/result
        type's bit width, and that operand/result types match and are
        purely-quantum `!prelim_hlep.lin<i<n>>` types.
        TODO: double-check the sign convention for the exponent
    }];

    let arguments = (ins F64:$angle, HamiltonianAttr:$hamiltonian, AnyType:$input);
    let results = (outs AnyType:$result);

    let assemblyFormat = "$angle `hamiltonian` $hamiltonian $input attr-dict `:` `(` type($angle) `,` type($input) `)` `->` type($result)";
}

def BaseChangeOp : PrelimHLEPOp<"base_change"> {
    let summary = "Distinguished isomorphism between the Z-, X-, and Y-basis linearizations of the same space.";
    let description = [{
        Converts between `!prelim_hlep.lin<i<n>>`, `!prelim_hlep.lin<!prelim_hlep.x<n>>`,
        and `!prelim_hlep.lin<!prelim_hlep.y<n>>`, which are the same vector
        space equipped with different distinguished bases. See "Base
        changes" in the design doc.

        **IR Realization:**
        ```mlir
        %qubit_in_x_basis = prelim_hlep.base_change %qubit_in_z_basis :
            !prelim_hlep.lin<i1> -> !prelim_hlep.lin<!prelim_hlep.x<1>>
        ```

        The verifier checks that the op is nested (directly or indirectly)
        within a `prelim_hlep.halo`-attributed function.

        TODO: verifier restricting operand/result types to
        `!prelim_hlep.lin<...>` over `i<n>`/`x<n>`/`y<n>` of matching `n`.
    }];

    let arguments = (ins AnyType:$input);
    let results = (outs AnyType:$result);

    let assemblyFormat = "$input attr-dict `:` type($input) `->` type($result)";
    let hasVerifier = 1;
}

def ConstantOp : PrelimHLEPOp<"constant"> {
    let summary = "A literal value of a linearized X- or Y-basis type.";
    let description = [{
        Constructs a constant term of `!prelim_hlep.lin<!prelim_hlep.x<n>>`
        or `!prelim_hlep.lin<!prelim_hlep.y<n>>` from a string of basis
        symbols (`+`/`-` for X, `->`/`<-` for Y). See "Base changes" in the
        design doc.

        **IR Realization:**
        ```mlir
        %xxx = prelim_hlep.constant "++-" : !prelim_hlep.lin<!prelim_hlep.x<3>>
        %yyy = prelim_hlep.constant "><>" : !prelim_hlep.lin<!prelim_hlep.y<3>>
        ```

        TODO: verifier checking that `value` consists only of valid basis
        symbols for the result type, with length matching the result type's
        `n`.
        TODO: consider defining a custom attribute instead of a string.
    }];

    let arguments = (ins StrAttr:$value);
    let results = (outs AnyType:$result);

    let assemblyFormat = "$value attr-dict `:` type($result)";
}

def UnitValueOp : PrelimHLEPOp<"unit_value"> {
    let summary = "Constructs the unique value of !prelim_hlep.linear_unit.";
    let description = [{
        Creates a `!prelim_hlep.linear_unit` value, e.g. to pass into a
        `LinearHalo` function called from a classical (non-haloed) context.
        See "Halo Unit Type" in the design doc.

        **IR Realization:**
        `%halo = prelim_hlep.unit_value : !prelim_hlep.linear_unit`
    }];

    let arguments = (ins);
    let results = (outs LinearUnitType:$result);

    let assemblyFormat = "attr-dict `:` type($result)";
}

#endif // INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPOPS_TD_
