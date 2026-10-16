// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_OQ3_IR_OQ3OPS_TD_
#define INCLUDE_QCC_DIALECT_OQ3_IR_OQ3OPS_TD_

include "qcc/Dialect/OQ3/IR/OQ3Attrs.td"
include "qcc/Dialect/OQ3/IR/OQ3Dialect.td"
include "qcc/Dialect/OQ3/IR/OQ3Types.td"
include "qcc/Dialect/Qcc/IR/QccTypes.td"

include "mlir/IR/CommonAttrConstraints.td"
include "mlir/IR/CommonTypeConstraints.td"
include "mlir/IR/OpBase.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// Shared definitions
//===----------------------------------------------------------------------===//

class OQ3_Op<string mnemonic, list<Trait> traits = []> : Op<OQ3_Dialect, mnemonic, traits>;

// Source text that has no effect on the program, such as a comment, still has to survive `canonicalize` and DCE. The
// operations that carry it write this resource, which aliases with nothing else.
def OQ3_SourceTextResource : Resource<"::qcc::oq3::SourceTextResource">;
def OQ3_WritesSourceText : MemoryEffects<[MemWrite<OQ3_SourceTextResource>]>;

def OQ3_QubitOrRegister : AnyTypeOf<[Qcc_QubitRefType, OQ3_QRegType, OQ3_UnknownType],
                                    "qubit reference or register">;

//===----------------------------------------------------------------------===//
// Program structure and directives
//===----------------------------------------------------------------------===//

def OQ3_DefinedOp : OQ3_Op<"defined", [OQ3_WritesSourceText]> {
  let summary = "source position of a global definition";
  let description = [{
        Global definitions (gates, subroutines, `const`s) are symbols of the module, so their position in the program
        is recorded by this marker in the entry body. The exporter prints each definition at its marker, and the
        verifier checks define-before-use against the order of the markers.

        Example:
        ```mlir
        oq3.defined @m
        ```
    }];

  let arguments = (ins FlatSymbolRefAttr:$symbol);
  let assemblyFormat = "$symbol attr-dict";
  let hasVerifier = 1;
}

def OQ3_IncludeOp : OQ3_Op<"include", [OQ3_WritesSourceText]> {
  let summary = "include statement";
  let description = [{
        `include "path";` at its position in the entry body. The `id` is unique within the module, and every
        statement the included file produced carries it as `oq3.from_include`. The content hash identifies the file
        that was read. An include that could not be found has the `unresolved` flag and produced nothing.

        `stdgates.inc` provides the standard gates, which are checked against a built-in signature table if the file remains unresolved.

        Example:
        ```mlir
        oq3.include "stdgates.inc" id 0
        oq3.include "vendor.inc" id 1 unresolved
        ```
    }];

  let arguments = (ins StrAttr:$path,
                       I64Attr:$id,
                       OptionalAttr<StrAttr>:$content_hash,
                       UnitAttr:$unresolved);
  let assemblyFormat = [{
        $path `id` $id (`hash` $content_hash^)? (`unresolved` $unresolved^)? attr-dict
    }];
  let hasVerifier = 1;
}

def OQ3_CommentOp : OQ3_Op<"comment", [OQ3_WritesSourceText]> {
  let summary = "standalone comment";
  let description = [{
        A comment on its own line(s), at its position among the statements. The text includes the comment markers, so
        that line and block comments are printed as written. Comments before the `OPENQASM` line have the `header`
        flag. A comment that follows a statement on the same line is the attribute `oq3.trailing_comment` of that
        statement instead.

        Example:
        ```mlir
        oq3.comment "// Prepare a Bell pair"
        ```
    }];

  let arguments = (ins StrAttr:$text, UnitAttr:$header);
  let assemblyFormat = "$text (`header` $header^)? attr-dict";
  let hasVerifier = 1;
}

def OQ3_PragmaOp : OQ3_Op<"pragma", [OQ3_WritesSourceText]> {
  let summary = "pragma directive";
  let description = [{
        `pragma text`: the rest of the line after `pragma`, verbatim. `hash_prefix` marks the older spelling
        `#pragma`.

        Example:
        ```mlir
        oq3.pragma "ibm.user alice account 12345678"
        ```
    }];

  let arguments = (ins StrAttr:$text, UnitAttr:$hash_prefix);
  let assemblyFormat = "$text (`hash_prefix` $hash_prefix^)? attr-dict";
  let hasVerifier = 1;
}

def OQ3_UnresolvedOp : OQ3_Op<"unresolved", [Pure]> {
  let summary = "use of a name from an unresolved include";
  let description = [{
        A name that resolves to nothing, in a program with an unresolved include that may define it. Its type is
        unknown. Only valid in a module with an unresolved `oq3.include`.

        Example:
        ```mlir
        %foo = oq3.unresolved "foo" : !oq3.unknown
        ```
    }];

  let arguments = (ins StrAttr:$name);
  let results = (outs OQ3_UnknownType:$result);
  let assemblyFormat = "$name attr-dict `:` qualified(type($result))";
}

def OQ3_UnresolvedCallOp : OQ3_Op<"unresolved_call"> {
  let summary = "call of a subroutine from an unresolved include";
  let description = [{
        `foo(args)` where `foo` resolves to nothing, in a program with an unresolved include that may define it.
        Without qubit arguments, the call must be a subroutine call. Only valid in a module with an unresolved
        `oq3.include`. All calls of the same name take the same number of arguments.

        Example:
        ```mlir
        %r = oq3.unresolved_call "foo"(%x) : (!oq3.int) -> !oq3.unknown
        ```
    }];

  let arguments = (ins StrAttr:$callee, Variadic<AnyType>:$args);
  let results = (outs OQ3_UnknownType:$result);
  let assemblyFormat = "$callee `(` $args `)` attr-dict `:` functional-type($args, $result)";
}

//===----------------------------------------------------------------------===//
// Declarations and storage
//===----------------------------------------------------------------------===//

def OQ3_QubitDeclOp : OQ3_Op<"qubit_decl", [OQ3_WritesSourceText]> {
  let summary = "qubit or qubit register declaration";
  let description = [{
        Declares the qubit `qubit q;` or the register `qubit[n] q;` and returns a reference to it. The `legacy` flag
        marks the old syntax `qreg q[n];`. The designator is the source expression of the size, which the result type
        holds evaluated. Allowed in the entry body only.

        Example:
        ```mlir
        %q = oq3.qubit_decl "q" : !qcc.qubit_ref
        %c2 = oq3.constant #oq3.int<2> : !oq3.int
        %r = oq3.qubit_decl "r" [%c2 : !oq3.int] legacy : !oq3.qreg<2>
        ```
    }];

  let arguments = (ins StrAttr:$name, Optional<AnyType>:$designator, UnitAttr:$legacy);
  let results = (outs AnyTypeOf<[Qcc_QubitRefType, OQ3_QRegType]>:$result);
  let assemblyFormat = [{
        $name (` ` `[` $designator^ `:` type($designator) `]`)? (`legacy` $legacy^)? attr-dict `:` qualified(type($result))
    }];
  let hasVerifier = 1;
}

def OQ3_PhysicalQubitOp : OQ3_Op<"physical_qubit", [Pure]> {
  let summary = "physical qubit";
  let description = [{
        A reference to the physical qubit `$index`. Physical qubits are not declared and are visible everywhere.

        Example:
        ```mlir
        %q = oq3.physical_qubit 3 : !qcc.qubit_ref
        ```
    }];

  let arguments = (ins ConfinedAttr<I64Attr, [IntNonNegative]>:$index);
  let results = (outs Qcc_QubitRefType:$result);
  let assemblyFormat = "$index attr-dict `:` qualified(type($result))";
}

def OQ3_DeclareOp : OQ3_Op<"declare", [OQ3_WritesSourceText, AttrSizedOperandSegments]> {
  let summary = "classical variable declaration";
  let description = [{
        Declares the classical variable `name` with an optional initial value and returns its storage. The `legacy`
        flag marks the old syntax `creg c[n];`. The designator is the source expression of the size, which the type
        holds evaluated.

        TODO: For now only `bit` and `bit[n]` variables can be declared.

        Example:
        ```mlir
        %c = oq3.declare "c" : !qcc.ref<!oq3.bit>
        %c2 = oq3.constant #oq3.int<2> : !oq3.int
        %d = oq3.declare "d" [%c2 : !oq3.int] = %bits : !oq3.bits<2> : !qcc.ref<!oq3.bits<2>>
        ```
    }];

  let arguments = (ins StrAttr:$name,
                       Optional<AnyType>:$designator,
                       Optional<AnyType>:$init,
                       UnitAttr:$legacy);
  let results = (outs Res<Qcc_RefType, "the variable's storage", [MemAlloc]>:$result);
  let assemblyFormat = [{
        $name (` ` `[` $designator^ `:` type($designator) `]`)? (`=` $init^ `:` type($init))? (`legacy` $legacy^)?
        attr-dict `:` qualified(type($result))
    }];
  let hasVerifier = 1;
}

def OQ3_SubrefOp : OQ3_Op<"subref", [Pure]> {
  let summary = "reference to a part of a variable";
  let description = [{
        The l-value `c[i]`: a reference to bit `i` of the bit register that `ref` holds. A negative index counts from
        the end.

        Example:
        ```mlir
        %c0 = oq3.subref %c[%i] : !qcc.ref<!oq3.bits<2>>, !oq3.int -> !qcc.ref<!oq3.bit>
        ```
    }];

  let arguments = (ins Qcc_RefType:$ref, AnyType:$index);
  let results = (outs Qcc_RefType:$result);
  let assemblyFormat = [{
        $ref `[` $index `]` attr-dict `:` qualified(type($ref)) `,` type($index) `->` qualified(type($result))
    }];
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Qubit aliasing
//===----------------------------------------------------------------------===//

def OQ3_QubitIndexOp : OQ3_Op<"qubit_index", [Pure]> {
  let summary = "qubit of a register";
  let description = [{
        `q[i]`: a reference to qubit `i` of the register `reg`. A negative index counts from the end.

        Example:
        ```mlir
        %q0 = oq3.qubit_index %q[%i] : !oq3.qreg<2>, !oq3.int
        ```
    }];

  let arguments = (ins AnyTypeOf<[OQ3_QRegType, OQ3_UnknownType]>:$reg, AnyType:$index);
  let results = (outs Qcc_QubitRefType:$result);
  let assemblyFormat = "$reg `[` $index `]` attr-dict `:` qualified(type($reg)) `,` type($index)";
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Expressions
//===----------------------------------------------------------------------===//

def OQ3_ConstantOp : OQ3_Op<"constant", [Pure, AllTypesMatch<["value", "result"]>]> {
  let summary = "literal";
  let description = [{
        An integer (`#oq3.int`), floating-point (`#oq3.float`), or bitstring (`#oq3.bitstring`) literal. Integer and
        floating-point literals have the unsized types `!oq3.int` and `!oq3.float`, a bitstring of `n` bits has type
        `!oq3.bits<n>`. An integer literal remembers the base it was written in (decimal if absent).

        The op deliberately is not `ConstantLike`: nothing folds at the `oq3` level.

        Example:
        ```mlir
        %c = oq3.constant #oq3.int<31> : !oq3.int radix hex
        %f = oq3.constant #oq3.float<"1.5e3"> : !oq3.float
        %b = oq3.constant #oq3.bitstring<"0101"> : !oq3.bits<4>
        ```
    }];

  let arguments = (ins TypedAttrInterface:$value,
                       OptionalAttr<OQ3_IntegerRadixAttr>:$radix);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$value (`radix` $radix^)? attr-dict";
  let hasVerifier = 1;
}

def OQ3_MathConstantOp : OQ3_Op<"math_constant", [Pure]> {
  let summary = "built-in math constant";
  let description = [{
        One of the constants π, τ, and ℯ. The `unicode` flag records the spelling `π` instead of `pi` (and so on), so
        that the export prints it as written.

        Example:
        ```mlir
        %pi = oq3.math_constant pi unicode : !oq3.float
        ```
    }];

  let arguments = (ins OQ3_MathConstantKindAttr:$kind, UnitAttr:$unicode);
  let results = (outs OQ3_UnsizedFloatType:$result);
  let assemblyFormat = "$kind (`unicode` $unicode^)? attr-dict `:` qualified(type($result))";
}

def OQ3_UnaryOp : OQ3_Op<"unary", [Pure, SameOperandsAndResultType]> {
  let summary = "unary operator";
  let description = [{
        `-x` on integers, floating-point numbers, and angles.

        Example:
        ```mlir
        %neg = oq3.unary neg %x : !oq3.float
        ```
    }];

  let arguments = (ins OQ3_UnaryKindAttr:$kind, AnyType:$operand);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$kind $operand attr-dict `:` type($result)";
  let hasVerifier = 1;
}

def OQ3_BinaryOp : OQ3_Op<"binary", [Pure]> {
  let summary = "binary operator";
  let description = [{
        `+ - * /` on integers, floating-point numbers, and angles. Both operands have the result type, except for
        scaling an angle by an integer (`angle * int`, `int * angle`, `angle / int`). Division of integers is integer
        division. The type is printed once if all three agree.

        Example:
        ```mlir
        %sum = oq3.binary add %a, %b : !oq3.float
        %half = oq3.binary div %theta, %c2 : (!qcc.angle, !oq3.int) -> !qcc.angle
        ```
    }];

  let arguments = (ins OQ3_BinaryKindAttr:$kind, AnyType:$lhs, AnyType:$rhs);
  let results = (outs AnyType:$result);
  let assemblyFormat = [{
        $kind $lhs `,` $rhs attr-dict `:` custom<BinaryTypes>(type($lhs), type($rhs), type($result))
    }];
  let hasVerifier = 1;
}

def OQ3_CastOp : OQ3_Op<"cast", [Pure]> {
  let summary = "type conversion";
  let description = [{
        Converts `input` to the result type. The importer inserts `implicit` casts to make operand types match, and
        the exporter does not print them. Supported for now: `!oq3.int` to `!oq3.float` and to `!oq3.bit`, and
        `!oq3.float` to `!qcc.angle`.

        Example:
        ```mlir
        %f = oq3.cast %i implicit : !oq3.int -> !oq3.float
        ```
    }];

  let arguments = (ins AnyType:$input, UnitAttr:$implicit);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$input (`implicit` $implicit^)? attr-dict `:` type($input) `->` type($result)";
  let hasVerifier = 1;
}

def OQ3_MeasureOp : OQ3_Op<"measure"> {
  let summary = "measurement";
  let description = [{
        `measure q`: measures a qubit into a bit, or a register of `n` qubits into `n` bits. `c = measure q;` stores
        the result, `measure q -> c;` stores it with the `oq3.arrow` flag on the store, and `measure q;` leaves it
        unused.

        Example:
        ```mlir
        %m = oq3.measure %q : !oq3.qreg<2> -> !oq3.bits<2>
        qcc.ref.store %m, %c {oq3.arrow} : !qcc.ref<!oq3.bits<2>>
        ```
    }];

  let arguments = (ins OQ3_QubitOrRegister:$qubits);
  let results = (outs AnyTypeOf<[OQ3_BitType, OQ3_BitsType, OQ3_UnknownType]>:$result);
  let assemblyFormat = "$qubits attr-dict `:` qualified(type($qubits)) `->` qualified(type($result))";
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Quantum instructions
//===----------------------------------------------------------------------===//

def OQ3_GateCallOp : OQ3_Op<"gate_call", [AttrSizedOperandSegments,
                                         DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "gate application";
  let description = [{
        Applies the gate `callee` with the angle parameters `params` to `qubits`. The callee is a standard gate of
        `stdgates.inc` (if included), one of the built-in gates `U` and `gphase`, or, in a module with an unresolved
        include, a gate it may define. Register operands broadcast: all of them have the same size, and the gate is
        applied once per index.

        Example:
        ```mlir
        oq3.gate_call @rx(%theta : !qcc.angle) [%q : !qcc.qubit_ref]
        oq3.gate_call @cx [%q0, %q1 : !qcc.qubit_ref, !qcc.qubit_ref]
        oq3.gate_call @gphase(%gamma : !qcc.angle)
        ```
    }];

  let arguments = (ins FlatSymbolRefAttr:$callee,
                       Variadic<AnyTypeOf<[Qcc_AngleType, OQ3_UnknownType]>>:$params,
                       Variadic<OQ3_QubitOrRegister>:$qubits);
  let assemblyFormat = [{
        $callee (`(` $params^ `:` type($params) `)`)? (`[` $qubits^ `:` type($qubits) `]`)? attr-dict
    }];
  let hasVerifier = 1;
}

def OQ3_ResetOp : OQ3_Op<"reset"> {
  let summary = "reset to |0>";
  let description = [{
        `reset q;`: resets a qubit, or every qubit of a register, to |0⟩.

        Example:
        ```mlir
        oq3.reset %q : !qcc.qubit_ref
        ```
    }];

  let arguments = (ins OQ3_QubitOrRegister:$qubits);
  let assemblyFormat = "$qubits attr-dict `:` type($qubits)";
}

def OQ3_BarrierOp : OQ3_Op<"barrier"> {
  let summary = "barrier";
  let description = [{
        `barrier q, r;`: no operation may be moved across the barrier on the given qubits. Without operands, the
        barrier applies to all qubits.

        Example:
        ```mlir
        oq3.barrier [%q, %r : !oq3.qreg<2>, !qcc.qubit_ref]
        oq3.barrier
        ```
    }];

  let arguments = (ins Variadic<OQ3_QubitOrRegister>:$qubits);
  let assemblyFormat = "(` ` `[` $qubits^ `:` type($qubits) `]`)? attr-dict";
}

#endif // INCLUDE_QCC_DIALECT_OQ3_IR_OQ3OPS_TD_
