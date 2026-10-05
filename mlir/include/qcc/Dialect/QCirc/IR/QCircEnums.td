// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCIRC_IR_QCIRCENUMS_TD_
#define INCLUDE_QCC_DIALECT_QCIRC_IR_QCIRCENUMS_TD_

include "mlir/IR/EnumAttr.td"

//===----------------------------------------------------------------------===//
// Gate kinds
//===----------------------------------------------------------------------===//

// There is no identity gate on purpose. A lowering that needs one uses `rz(0)`.

class QCirc_GateCase<string sym, int val, string str, int arity> : I32EnumCase<sym, val, str> {
  int numParams = arity;
}

def QCirc_SingleGateKind : I32Enum<"SingleGateKind", "single-qubit gate kind", [
    // C++ name, id, IR name, num params
    QCirc_GateCase<"X", 0, "x", 0>,
    QCirc_GateCase<"Y", 1, "y", 0>,
    QCirc_GateCase<"Z", 2, "z", 0>,
    QCirc_GateCase<"H", 3, "h", 0>,
    QCirc_GateCase<"S", 4, "s", 0>,
    QCirc_GateCase<"Sdg", 5, "sdg", 0>,
    QCirc_GateCase<"T", 6, "t", 0>,
    QCirc_GateCase<"Tdg", 7, "tdg", 0>,
    QCirc_GateCase<"SX", 8, "sx", 0>,       // sx * sx = x
    QCirc_GateCase<"SXdg", 9, "sxdg", 0>,
    QCirc_GateCase<"RX", 10, "rx", 1>,      // rx(theta) = exp(-i * theta/2 * X)
    QCirc_GateCase<"RY", 11, "ry", 1>,
    QCirc_GateCase<"RZ", 12, "rz", 1>,
    QCirc_GateCase<"UZXZ", 13, "u_zxz", 3>, // u_zxz(z1, x, z2) = rz(z2) * rx(x) * rz(z1)
    QCirc_GateCase<"UZYZ", 14, "u_zyz", 3>, // u_zyz(z1, y, z2) = rz(z2) * ry(y) * rz(z1)
]> {
  let cppNamespace = "::qcc::qcirc";
}

def QCirc_PairGateKind : I32Enum<"PairGateKind", "two-qubit gate kind", [
    // C++ name, id, IR name, num params
    QCirc_GateCase<"CX", 0, "cx", 0>,
    QCirc_GateCase<"CY", 1, "cy", 0>,
    QCirc_GateCase<"CZ", 2, "cz", 0>,
    QCirc_GateCase<"SWAP", 3, "swap", 0>,
    QCirc_GateCase<"iSWAP", 4, "iswap", 0>,
    QCirc_GateCase<"CP", 5, "cp", 1>,       // cp(theta) = diag(1, 1, 1, e^{i * theta})
    QCirc_GateCase<"CRZ", 6, "crz", 1>,     // crz(theta) = diag(1, 1, e^{-i * theta/2}, e^{i * theta/2})
    QCirc_GateCase<"RXX", 7, "rxx", 1>,     // rxx(theta) = exp(-i * theta/2 * X (x) X)
    QCirc_GateCase<"RYY", 8, "ryy", 1>,
    QCirc_GateCase<"RZZ", 9, "rzz", 1>,
]> {
  let cppNamespace = "::qcc::qcirc";
}

// Global gates act on several qubits jointly. Their parameter is not one angle per gate but a matrix over the qubits
// (see `qcirc.global`), so they carry no arity here.
def QCirc_GlobalGateKind : I32Enum<"GlobalGateKind", "global gate kind", [
    // C++ name, id, IR name
    I32EnumCase<"ZZ", 0, "zz">,
]> {
  let cppNamespace = "::qcc::qcirc";
}

//===----------------------------------------------------------------------===//
// Bases
//===----------------------------------------------------------------------===//

// The basis of a measurement or a reset.
def QCirc_Basis : I32Enum<"Basis", "single-qubit basis", [
    // C++ name, id, IR name
    I32EnumCase<"Z", 0, "z">, // |0>, |1>
    I32EnumCase<"X", 1, "x">, // |+>, |->
]> {
  let cppNamespace = "::qcc::qcirc";
}

#endif // INCLUDE_QCC_DIALECT_QCIRC_IR_QCIRCENUMS_TD_
