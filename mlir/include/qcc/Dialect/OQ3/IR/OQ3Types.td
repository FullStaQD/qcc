// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_OQ3_IR_OQ3TYPES_TD_
#define INCLUDE_QCC_DIALECT_OQ3_IR_OQ3TYPES_TD_

include "qcc/Dialect/OQ3/IR/OQ3Dialect.td"

include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// OQ3 types
//===----------------------------------------------------------------------===//

class OQ3_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<OQ3_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

// A type with a size that is printed as `<n>`, or `<?>` if it depends on a name from an unresolved include.
class OQ3_SizedType<string name, string typeMnemonic> : OQ3_Type<name, typeMnemonic> {
  let parameters = (ins "int64_t":$size);
  let hasCustomAssemblyFormat = 1;
  let genVerifyDecl = 1;

  let extraClassDeclaration = [{
    /// Whether the size is unknown (`?`).
    bool hasUnknownSize() const { return ::mlir::ShapedType::isDynamic(getSize()); }
  }];
}

def OQ3_QRegType : OQ3_SizedType<"QReg", "qreg"> {
  let summary = "reference to a qubit register";
  let description = [{
        A reference to `size` qubits, from `qubit[n]` or `qreg q[n]`. Operations that act on qubits broadcast over a
        register. The size may be zero.

        Example:
        ```mlir
        !oq3.qreg<2>
        ```
    }];
}

def OQ3_BitType : OQ3_Type<"Bit", "bit"> {
  let summary = "single bit";
  let description = [{
        A single classical bit, OpenQASM's `bit`. It is distinct from `!oq3.bits<1>`.
    }];
}

def OQ3_BitsType : OQ3_SizedType<"Bits", "bits"> {
  let summary = "bit register";
  let description = [{
        A register of `size` bits, OpenQASM's `bit[n]` and `creg c[n]`.
    }];
}

def OQ3_UnsizedIntType : OQ3_Type<"UnsizedInt", "int"> {
  let summary = "integer of unspecified width";
  let description = [{
        OpenQASM's unsized `int`, whose width the target defines. Integer literals have this type.
    }];
}

def OQ3_UnsizedFloatType : OQ3_Type<"UnsizedFloat", "float"> {
  let summary = "floating-point number of unspecified width";
  let description = [{
        OpenQASM's unsized `float`, whose precision the target defines. Floating-point literals and the math constants
        have this type.
    }];
}

def OQ3_UnknownType : OQ3_Type<"Unknown", "unknown"> {
  let summary = "type of a name from an unresolved include";
  let description = [{
        A name that is not defined anywhere may come from an include that could not be found (see the importer's
        `--oq3-allow-unresolved-includes`). Its type is unknown, and so is the type of everything computed from it.
        Expressions accept unknown operands, and no casts to or from this type exist.

        Only valid in a module with an unresolved `oq3.include`.
    }];
}

#endif // INCLUDE_QCC_DIALECT_OQ3_IR_OQ3TYPES_TD_
