// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_OQ3_IR_OQ3ENUMS_TD_
#define INCLUDE_QCC_DIALECT_OQ3_IR_OQ3ENUMS_TD_

include "mlir/IR/EnumAttr.td"

def OQ3_BinaryKind : I32Enum<"BinaryKind", "binary operator", [
    // C++ name, id, IR name
    I32EnumCase<"Add", 0, "add">, // +
    I32EnumCase<"Sub", 1, "sub">, // -
    I32EnumCase<"Mul", 2, "mul">, // *
    I32EnumCase<"Div", 3, "div">, // /
]> {
  let cppNamespace = "::qcc::oq3";
}

def OQ3_UnaryKind : I32Enum<"UnaryKind", "unary operator", [
    // C++ name, id, IR name
    I32EnumCase<"Neg", 0, "neg">, // -
]> {
  let cppNamespace = "::qcc::oq3";
}

def OQ3_MathConstantKind : I32Enum<"MathConstantKind", "built-in math constant", [
    // C++ name, id, IR name
    I32EnumCase<"Pi", 0, "pi">,       // pi or π
    I32EnumCase<"Tau", 1, "tau">,     // tau or τ
    I32EnumCase<"Euler", 2, "euler">, // euler or ℯ
]> {
  let cppNamespace = "::qcc::oq3";
}

// The base an integer literal is written in. The value is the base.
def OQ3_IntegerRadix : I32Enum<"IntegerRadix", "base of an integer literal", [
    // C++ name, id, IR name
    I32EnumCase<"Bin", 2, "bin">,  // 0b101
    I32EnumCase<"Oct", 8, "oct">,  // 0o17
    I32EnumCase<"Dec", 10, "dec">, // 15
    I32EnumCase<"Hex", 16, "hex">, // 0x1F
]> {
  let cppNamespace = "::qcc::oq3";
}

#endif // INCLUDE_QCC_DIALECT_OQ3_IR_OQ3ENUMS_TD_
