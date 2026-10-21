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

// Statements without uses that still have to survive `canonicalize` and DCE, because they shape the program: the
// position markers of global definitions, includes, pragmas, and qubit declarations. They write this resource, which
// aliases with nothing else, so that they do not block analyses of other memory.
def OQ3_ProgramStructureResource : Resource<"::qcc::oq3::ProgramStructureResource">;
def OQ3_WritesProgramStructure : MemoryEffects<[MemWrite<OQ3_ProgramStructureResource>]>;

def OQ3_QubitOrRegister : AnyTypeOf<[Qcc_QubitRefType, OQ3_QRegType],
                                    "qubit reference or register">;

//===----------------------------------------------------------------------===//
// Program structure and directives
//===----------------------------------------------------------------------===//

def OQ3_DefinedOp : OQ3_Op<"defined", [OQ3_WritesProgramStructure]> {
  let summary = "source position of a global definition";
  let description = [{
        Global definitions (gates, subroutines, `const`s) are symbols of the module, so their position in the program
        is recorded by this marker in the entry body. The exporter prints each definition at its marker, and the
        verifier checks define-before-use against the order of the markers.

        Example:
        ```mlir
        module attributes {oq3.version = #oq3.version<3, 1>} {
          func.func private @f()                 // MLIR definition of the function.
          func.func @main() attributes {qcc.entry_point} {
            %q = oq3.qubit_decl "q" : !qcc.qubit_ref
            oq3.defined @f                       // location of the definition in the OpenQASM program
            return
          }
        }
        ```
    }];

  let arguments = (ins FlatSymbolRefAttr:$symbol);
  let assemblyFormat = "$symbol attr-dict";
  let hasVerifier = 1;
}

def OQ3_IncludeOp : OQ3_Op<"include", [OQ3_WritesProgramStructure]> {
  let summary = "include statement";
  let description = [{
        `include "path";` at its position in the entry body. The `id` is unique within the module, and every
        statement the included file produced carries it as `oq3.from_include`, so that the export prints the include
        instead of them.

        `stdgates.inc` is not read. Including it makes the standard gates available, which are checked against a
        built-in signature table.

        Example:
        ```mlir
        oq3.include "stdgates.inc" id 0
        ```
    }];

  let arguments = (ins StrAttr:$path, I64Attr:$id);
  let assemblyFormat = "$path `id` $id attr-dict";
  let hasVerifier = 1;
}

def OQ3_PragmaOp : OQ3_Op<"pragma", [OQ3_WritesProgramStructure]> {
  let summary = "pragma directive";
  let description = [{
        A `pragma` line. `text` is the rest of the line after the keyword, verbatim. The importer also reads the older
        spelling `#pragma`, and the export prints `pragma`.

        Example:
        ```mlir
        oq3.pragma "ibm.user alice account 12345678"
        ```
    }];

  let arguments = (ins StrAttr:$text);
  let assemblyFormat = "$text attr-dict";
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Declarations and storage
//===----------------------------------------------------------------------===//

def OQ3_QubitDeclOp : OQ3_Op<"qubit_decl", [OQ3_WritesProgramStructure]> {
  let summary = "qubit or qubit register declaration";
  let description = [{
        Declares the qubit `qubit q;` or the register `qubit[n] q;` (or `qreg q[n];`) and returns a reference to it.
        The designator is the source expression of the size, which the result type
        holds evaluated. Allowed in the entry body only.

        Example:
        ```mlir
        %q = oq3.qubit_decl "q" : !qcc.qubit_ref
        %c2 = oq3.constant #oq3.int<2> : !oq3.int
        %r = oq3.qubit_decl "r" [%c2 : !oq3.int] : !oq3.qreg<2>
        ```
    }];

  let arguments = (ins StrAttr:$name, Optional<AnyType>:$designator);
  let results = (outs AnyTypeOf<[Qcc_QubitRefType, OQ3_QRegType]>:$result);
  let assemblyFormat = [{
        $name (` ` `[` $designator^ `:` type($designator) `]`)? attr-dict `:` qualified(type($result))
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

def OQ3_DeclareOp : OQ3_Op<"declare", [OQ3_WritesProgramStructure, AttrSizedOperandSegments]> {
  let summary = "classical variable declaration";
  let description = [{
        Declares the classical variable `name` with an optional initial value and returns its storage. `creg c[n];` is
        the same as `bit[n] c;`. The designator is the source expression of the size, which the type
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
                       Optional<AnyType>:$init);
  let results = (outs Res<Qcc_RefType, "the variable's storage", [MemAlloc]>:$result);
  let assemblyFormat = [{
        $name (` ` `[` $designator^ `:` type($designator) `]`)? (`=` $init^ `:` type($init))? attr-dict `:`
        qualified(type($result))
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

  let arguments = (ins OQ3_QRegType:$reg, AnyType:$index);
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
        `!oq3.bits<n>`.

        Example:
        ```mlir
        %c = oq3.constant #oq3.int<31> : !oq3.int
        %f = oq3.constant #oq3.float<"1.5e3"> : !oq3.float
        %b = oq3.constant #oq3.bitstring<"0101"> : !oq3.bits<4>
        ```
    }];

  let arguments = (ins TypedAttrInterface:$value);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$value attr-dict";
  let hasVerifier = 1;
}

def OQ3_MathConstantOp : OQ3_Op<"math_constant", [Pure]> {
  let summary = "built-in math constant";
  let description = [{
        One of the constants π, τ, and ℯ, spelled `pi`, `tau`, and `euler` on export.

        Example:
        ```mlir
        %pi = oq3.math_constant pi : !oq3.float
        ```
    }];

  let arguments = (ins OQ3_MathConstantKindAttr:$kind);
  let results = (outs OQ3_UnsizedFloatType:$result);
  let assemblyFormat = "$kind attr-dict `:` qualified(type($result))";
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
        `c = measure q`: measures a qubit into a bit, or a register of `n` qubits into `n` bits.

        Example:
        ```mlir
        %m = oq3.measure %q : !oq3.qreg<2> -> !oq3.bits<2>
        qcc.ref.store %m, %c : !qcc.ref<!oq3.bits<2>>
        ```
    }];

  let arguments = (ins OQ3_QubitOrRegister:$qubits);
  let results = (outs AnyTypeOf<[OQ3_BitType, OQ3_BitsType]>:$result);
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
        `stdgates.inc` (if included) or one of the built-in gates `U` and `gphase`. Register operands broadcast: all of them have the same size, and the gate is
        applied once per index.

        Example:
        ```mlir
        oq3.gate_call @rx(%theta : !qcc.angle) [%q : !qcc.qubit_ref]
        oq3.gate_call @cx [%q0, %q1 : !qcc.qubit_ref, !qcc.qubit_ref]
        oq3.gate_call @gphase(%gamma : !qcc.angle)
        ```
    }];

  let arguments = (ins FlatSymbolRefAttr:$callee,
                       Variadic<Qcc_AngleType>:$params,
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
