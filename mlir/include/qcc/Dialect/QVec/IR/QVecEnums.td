// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QVEC_IR_QVECENUMS_TD_
#define INCLUDE_QCC_DIALECT_QVEC_IR_QVECENUMS_TD_

include "mlir/IR/EnumAttr.td"

//===----------------------------------------------------------------------===//
// Gate kinds
//===----------------------------------------------------------------------===//

// TODO: The gate set enums are fixed for now. In the future we might want to make the gate set configurable: It could
// be queried via QDMI.

class QVec_GateCase<string sym, int val, string str, int arity> : I32EnumCase<sym, val, str> {
  int numParams = arity;
}

def QVec_SingleGateKind : I32Enum<"SingleGateKind", "single-qubit gate kind", [
    // C++ name, id, IR name, num params
    QVec_GateCase<"I", 0, "i", 0>,
    QVec_GateCase<"H", 1, "h", 0>,
    QVec_GateCase<"X", 2, "x", 0>,
    QVec_GateCase<"Y", 3, "y", 0>,
    QVec_GateCase<"Z", 4, "z", 0>,
    QVec_GateCase<"S", 5, "s", 0>,
    QVec_GateCase<"Sdg", 6, "sdg", 0>,
    QVec_GateCase<"T", 7, "t", 0>,
    QVec_GateCase<"Tdg", 8, "tdg", 0>,
    QVec_GateCase<"RX", 9, "rx", 1>,       // rx(theta) = exp(-i * theta/2 * X)
    QVec_GateCase<"RY", 10, "ry", 1>,
    QVec_GateCase<"RZ", 11, "rz", 1>,
    QVec_GateCase<"UZXZ", 12, "u_zxz", 3>, // u_zxz(z1, x, z2) = rz(z2) * rx(x) * rz(z1)
]> {
  let cppNamespace = "::qcc::qvec";
}

def QVec_PairGateKind : I32Enum<"PairGateKind", "two-qubit gate kind", [
    // C++ name, id, IR name, num params
    QVec_GateCase<"CX", 0, "cx", 0>,
    QVec_GateCase<"CY", 1, "cy", 0>,
    QVec_GateCase<"CZ", 2, "cz", 0>,
    QVec_GateCase<"iSWAP", 3, "iswap", 0>,
    QVec_GateCase<"RZZ", 4, "rzz", 1>,     // rzz(theta) = exp(-i * theta/2 * Z (x) Z)
    QVec_GateCase<"CP", 5, "cp", 1>,       // cp(theta) = diag(1, 1, 1, e^{i * theta})
]> {
  let cppNamespace = "::qcc::qvec";
}

// Global gates act on all lanes of a qubit vector jointly. Their parameters are not lane-aligned vectors but a matrix
// over the lanes (see `qvec.global`), so they carry no arity here.
def QVec_GlobalGateKind : I32Enum<"GlobalGateKind", "global gate kind", [
    // C++ name, id, IR name
    I32EnumCase<"ZZ", 0, "zz">,
]> {
  let cppNamespace = "::qcc::qvec";
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECENUMS_TD_
