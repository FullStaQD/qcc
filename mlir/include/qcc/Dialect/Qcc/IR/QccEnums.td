// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCC_IR_QCCENUMS_TD_
#define INCLUDE_QCC_DIALECT_QCC_IR_QCCENUMS_TD_

include "mlir/IR/EnumAttr.td"

//===----------------------------------------------------------------------===//
// Gate kinds
//===----------------------------------------------------------------------===//

// The gates of `qcirc` and `qref`.

class Qcc_GateCase<string sym, int val, string str, int numParamsVal> : I32EnumCase<sym, val, str> {
  int numParams = numParamsVal;
}

def Qcc_SingleGateKind : I32Enum<"SingleGateKind", "single-qubit gate kind", [
    // C++ name, id, IR name, num params
    // No identity gate on purpose. We recommend to "decompose" it into `rz(0)`.
    Qcc_GateCase<"X", 0, "x", 0>,
    Qcc_GateCase<"Y", 1, "y", 0>,
    Qcc_GateCase<"Z", 2, "z", 0>,
    Qcc_GateCase<"H", 3, "h", 0>,
    Qcc_GateCase<"S", 4, "s", 0>,
    Qcc_GateCase<"Sdg", 5, "sdg", 0>,
    Qcc_GateCase<"T", 6, "t", 0>,
    Qcc_GateCase<"Tdg", 7, "tdg", 0>,
    Qcc_GateCase<"SX", 8, "sx", 0>,       // sx = sqrt(x)
    Qcc_GateCase<"SXdg", 9, "sxdg", 0>,
    Qcc_GateCase<"RX", 10, "rx", 1>,      // rx(theta) = exp(-i * theta/2 * X)
    Qcc_GateCase<"RY", 11, "ry", 1>,
    Qcc_GateCase<"RZ", 12, "rz", 1>,
    Qcc_GateCase<"UZXZ", 13, "u_zxz", 3>, // u_zxz(z1, x, z2) = rz(z2) * rx(x) * rz(z1)
    Qcc_GateCase<"UZYZ", 14, "u_zyz", 3>, // u_zyz(z1, y, z2) = rz(z2) * ry(y) * rz(z1)
]> {
  let cppNamespace = "::qcc";
}

def Qcc_PairGateKind : I32Enum<"PairGateKind", "two-qubit gate kind", [
    // C++ name, id, IR name, num params
    Qcc_GateCase<"CX", 0, "cx", 0>,
    Qcc_GateCase<"CY", 1, "cy", 0>,
    Qcc_GateCase<"CZ", 2, "cz", 0>,
    Qcc_GateCase<"SWAP", 3, "swap", 0>,
    Qcc_GateCase<"iSWAP", 4, "iswap", 0>,
    Qcc_GateCase<"CP", 5, "cp", 1>,       // cp(theta) = diag(1, 1, 1, e^{i * theta})
    Qcc_GateCase<"CRZ", 6, "crz", 1>,     // crz(theta) = diag(1, 1, e^{-i * theta/2}, e^{i * theta/2})
    Qcc_GateCase<"RXX", 7, "rxx", 1>,     // rxx(theta) = exp(-i * theta/2 * X (x) X)
    Qcc_GateCase<"RYY", 8, "ryy", 1>,
    Qcc_GateCase<"RZZ", 9, "rzz", 1>,
]> {
  let cppNamespace = "::qcc";
}

//===----------------------------------------------------------------------===//
// Bases
//===----------------------------------------------------------------------===//

// The basis of a measurement or a reset.
def Qcc_Basis : I32Enum<"Basis", "single-qubit basis", [
    // C++ name, id, IR name
    I32EnumCase<"Z", 0, "z">, // |0>, |1>
    I32EnumCase<"X", 1, "x">, // |+>, |->
]> {
  let cppNamespace = "::qcc";
}

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCENUMS_TD_
