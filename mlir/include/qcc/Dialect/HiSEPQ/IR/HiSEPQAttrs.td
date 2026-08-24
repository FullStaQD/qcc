// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQATTRS_TD_
#define INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQATTRS_TD_

include "qcc/Dialect/HiSEPQ/IR/HiSEPQDialect.td"

include "mlir/IR/EnumAttr.td"

//===----------------------------------------------------------------------===//
// Gate kinds
//===----------------------------------------------------------------------===//

def HiSEPQ_SingleGate : I32Enum<"SingleGate", "single-qubit gate kind", [
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
  let cppNamespace = "::qcc::hisepq";
}

def HiSEPQ_PairGate : I32Enum<"PairGate", "two-qubit gate kind", [
    I32EnumCase<"CX", 0, "cx">,
    I32EnumCase<"CY", 1, "cy">,
    I32EnumCase<"CZ", 2, "cz">,
    I32EnumCase<"iSWAP", 3, "iswap">,
]> {
  let cppNamespace = "::qcc::hisepq";
}

def HiSEPQ_SingleGateAttr : EnumAttr<HiSEPQDialect, HiSEPQ_SingleGate, "single_gate"> {
  let assemblyFormat = "$value";
}

def HiSEPQ_PairGateAttr : EnumAttr<HiSEPQDialect, HiSEPQ_PairGate, "pair_gate"> {
  let assemblyFormat = "$value";
}

#endif // INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQATTRS_TD_
