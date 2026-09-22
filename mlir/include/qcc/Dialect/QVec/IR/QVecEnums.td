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

// A gate kind together with the number of angle parameters the gate takes. The op verifiers and the generated
// `getNumParams` (see QVecAttrs.td) read the arity from here, so it is defined exactly once.
class QVec_GateCase<string sym, int val, string str, int arity> : I32EnumCase<sym, val, str> {
  int numParams = arity;
}

// Parameter meaning (all angles in radians, one per lane):
//   rx(theta), ry(theta), rz(theta): rotation by theta about the respective axis, e.g. rz(theta) = diag(e^{-i
//   theta/2}, e^{i theta/2}).
//   u_zxz(z1, x, z2): Rz(z2) * Rx(x) * Rz(z1), i.e. z1 is applied first. Any single-qubit unitary can be written this
//   way, up to a global phase.
def QVec_SingleGate : I32Enum<"SingleGate", "single-qubit gate kind", [
    QVec_GateCase<"I", 0, "i", 0>,
    QVec_GateCase<"H", 1, "h", 0>,
    QVec_GateCase<"X", 2, "x", 0>,
    QVec_GateCase<"Y", 3, "y", 0>,
    QVec_GateCase<"Z", 4, "z", 0>,
    QVec_GateCase<"S", 5, "s", 0>,
    QVec_GateCase<"Sdg", 6, "sdg", 0>,
    QVec_GateCase<"T", 7, "t", 0>,
    QVec_GateCase<"Tdg", 8, "tdg", 0>,
    QVec_GateCase<"RX", 9, "rx", 1>,
    QVec_GateCase<"RY", 10, "ry", 1>,
    QVec_GateCase<"RZ", 11, "rz", 1>,
    QVec_GateCase<"UZXZ", 12, "u_zxz", 3>,
]> {
  let cppNamespace = "::qcc::qvec";
}

// Parameter meaning (lane-wise, radians):
//   rzz(theta): exp(-i theta/2 Z (x) Z).
//   cp(theta): controlled phase, diag(1, 1, 1, e^{i theta}); the left operand is the control (symmetric anyway).
def QVec_PairGate : I32Enum<"PairGate", "two-qubit gate kind", [
    QVec_GateCase<"CX", 0, "cx", 0>,
    QVec_GateCase<"CY", 1, "cy", 0>,
    QVec_GateCase<"CZ", 2, "cz", 0>,
    QVec_GateCase<"iSWAP", 3, "iswap", 0>,
    QVec_GateCase<"RZZ", 4, "rzz", 1>,
    QVec_GateCase<"CP", 5, "cp", 1>,
]> {
  let cppNamespace = "::qcc::qvec";
}

// Global gates act on all lanes of a qubit vector jointly. Their parameters are not lane-aligned vectors but a matrix
// over the lanes (see `qvec.global`), so they carry no arity here.
def QVec_GlobalGate : I32Enum<"GlobalGate", "global gate kind", [
    I32EnumCase<"ZZ", 0, "zz">,
]> {
  let cppNamespace = "::qcc::qvec";
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECENUMS_TD_
