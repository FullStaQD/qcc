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

// A type with a non-negative size, printed as `<n>`.
class OQ3_SizedType<string name, string typeMnemonic> : OQ3_Type<name, typeMnemonic> {
  let parameters = (ins "int64_t":$size);
  let assemblyFormat = "`<` $size `>`";
  let genVerifyDecl = 1;
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

#endif // INCLUDE_QCC_DIALECT_OQ3_IR_OQ3TYPES_TD_
