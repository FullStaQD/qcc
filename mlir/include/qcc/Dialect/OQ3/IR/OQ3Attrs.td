// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_OQ3_IR_OQ3ATTRS_TD_
#define INCLUDE_QCC_DIALECT_OQ3_IR_OQ3ATTRS_TD_

include "qcc/Dialect/OQ3/IR/OQ3Dialect.td"
include "qcc/Dialect/OQ3/IR/OQ3Enums.td"

include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/BuiltinAttributeInterfaces.td"
include "mlir/IR/EnumAttr.td"

//===----------------------------------------------------------------------===//
// Program attributes
//===----------------------------------------------------------------------===//

def OQ3_VersionAttr : AttrDef<OQ3_Dialect, "Version"> {
  let mnemonic = "version";
  let summary = "OpenQASM language version of a program";
  let description = [{
        The language version that the program's `OPENQASM` line selects: `#oq3.version<3, 1>` for `OPENQASM 3.1;`, and
        `#oq3.version<3, 0>` for `OPENQASM 3;`. A program without that line gets qcc's default version.

        TEMPORARY: `OPENQASM 3.2;` selects the current live specification, which has no release number yet.

        As the module attribute `oq3.version`, it marks the module as an OpenQASM program. Its verifier checks the
        program as a whole: the entry function, the `oq3.defined` markers, and the include tags.
    }];

  let parameters = (ins "unsigned":$major, "unsigned":$minor);
  let assemblyFormat = "`<` $major `,` $minor `>`";
  let genVerifyDecl = 1;
}

def OQ3_AnnotationAttr : AttrDef<OQ3_Dialect, "Annotation"> {
  let mnemonic = "annotation";
  let summary = "annotation of a statement";
  let description = [{
        An annotation line `@ns.name rest of line` before a statement. The annotations of a statement are the array
        attribute `oq3.annotations` on the operation the statement is printed from, in source order.

        Example:
        ```mlir
        oq3.gate_call @h [%q : !qcc.qubit_ref] {oq3.annotations = [#oq3.annotation<"ns.name", "args">]}
        ```
    }];

  let parameters = (ins StringRefParameter<"keyword without the `@`">:$name,
                        StringRefParameter<"the rest of the line, possibly empty">:$content);
  let assemblyFormat = "`<` $name `,` $content `>`";
  let genVerifyDecl = 1;
}

//===----------------------------------------------------------------------===//
// Literals
//===----------------------------------------------------------------------===//

def OQ3_IntLiteralAttr : AttrDef<OQ3_Dialect, "IntLiteral", [TypedAttrInterface]> {
  let mnemonic = "int";
  let summary = "integer literal of arbitrary precision";
  let description = [{
        The non-negative value of an integer literal, of type `!oq3.int`.

        Example: `#oq3.int<31> : !oq3.int`
    }];

  let parameters = (ins APIntParameter<"the value, in the fewest bits that hold it">:$value,
                        AttributeSelfTypeParameter<"">:$type);
  let hasCustomAssemblyFormat = 1;
  let genVerifyDecl = 1;

  let skipDefaultBuilders = 1;
  let builders = [
    // Stores `value` with the fewest bits that hold it, so that equal values are equal attributes.
    AttrBuilderWithInferredContext<(ins "const ::llvm::APInt&":$value, "::mlir::Type":$type), [{
      const unsigned width = ::std::max(1U, value.getActiveBits());
      return $_get(type.getContext(), value.zextOrTrunc(width), type);
    }]>
  ];
}

def OQ3_FloatLiteralAttr : AttrDef<OQ3_Dialect, "FloatLiteral", [TypedAttrInterface]> {
  let mnemonic = "float";
  let summary = "floating-point literal";
  let description = [{
        A floating-point literal as written (without digit separators), of type `!oq3.float`. The text commits to no
        precision.

        Example: `#oq3.float<"1.5e3"> : !oq3.float`
    }];

  let parameters = (ins StringRefParameter<"the literal's text">:$text,
                        AttributeSelfTypeParameter<"">:$type);
  let assemblyFormat = "`<` $text `>`";
  let genVerifyDecl = 1;
}

def OQ3_BitstringAttr : AttrDef<OQ3_Dialect, "Bitstring", [TypedAttrInterface]> {
  let mnemonic = "bitstring";
  let summary = "bitstring literal";
  let description = [{
        A bitstring literal such as `"0101"` (without digit separators). Its first character is the most significant
        bit. A bitstring of `n` bits has type `!oq3.bits<n>`.

        Example: `#oq3.bitstring<"0101"> : !oq3.bits<4>`
    }];

  let parameters = (ins StringRefParameter<"the bits, a non-empty string of `0` and `1`">:$bits,
                        AttributeSelfTypeParameter<"">:$type);
  let assemblyFormat = "`<` $bits `>`";
  let genVerifyDecl = 1;
}

//===----------------------------------------------------------------------===//
// Enum attributes
//===----------------------------------------------------------------------===//

def OQ3_BinaryKindAttr : EnumAttr<OQ3_Dialect, OQ3_BinaryKind, "binary_kind"> {
  let assemblyFormat = "$value";
}

def OQ3_UnaryKindAttr : EnumAttr<OQ3_Dialect, OQ3_UnaryKind, "unary_kind"> {
  let assemblyFormat = "$value";
}

def OQ3_MathConstantKindAttr : EnumAttr<OQ3_Dialect, OQ3_MathConstantKind, "math_constant_kind"> {
  let assemblyFormat = "$value";
}

#endif // INCLUDE_QCC_DIALECT_OQ3_IR_OQ3ATTRS_TD_
