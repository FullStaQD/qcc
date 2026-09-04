// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QVEC_IR_QVECATTRS_TD_
#define INCLUDE_QCC_DIALECT_QVEC_IR_QVECATTRS_TD_

include "qcc/Dialect/QVec/IR/QVecDialect.td"

include "mlir/IR/EnumAttr.td"

//===----------------------------------------------------------------------===//
// Gate kinds
//===----------------------------------------------------------------------===//

// TODO: The two gate set enums are a simple placeholder for now. They are definitely not complete; Rotations are
// missing and can be added once qvec supports single-target-one-parameter gates. In the future we might want to make
// the gate set configurable: It could be queried via QDMI.

def QVec_SingleGate : I32Enum<"SingleGate", "single-qubit gate kind", [
    I32EnumCase<"I", 0, "i">,
    I32EnumCase<"H", 1, "h">,
    I32EnumCase<"X", 2, "x">,
    I32EnumCase<"Y", 3, "y">,
    I32EnumCase<"Z", 4, "z">,
    I32EnumCase<"S", 5, "s">,
    I32EnumCase<"Sdg", 6, "sdg">,
    I32EnumCase<"T", 7, "t">,
    I32EnumCase<"Tdg", 8, "tdg">,
]> {
  let cppNamespace = "::qcc::qvec";
}

def QVec_PairGate : I32Enum<"PairGate", "two-qubit gate kind", [
    I32EnumCase<"CX", 0, "cx">,
    I32EnumCase<"CY", 1, "cy">,
    I32EnumCase<"CZ", 2, "cz">,
    I32EnumCase<"iSWAP", 3, "iswap">,
]> {
  let cppNamespace = "::qcc::qvec";
}

def QVec_SingleGateAttr : EnumAttr<QVecDialect, QVec_SingleGate, "single_gate"> {
  let assemblyFormat = "$value";
}

def QVec_PairGateAttr : EnumAttr<QVecDialect, QVec_PairGate, "pair_gate"> {
  let assemblyFormat = "$value";
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECATTRS_TD_
