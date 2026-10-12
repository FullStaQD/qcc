// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_HLEPGATE_IR_HLEPGATEATTRS_TD_
#define INCLUDE_QCC_DIALECT_HLEPGATE_IR_HLEPGATEATTRS_TD_

include "qcc/Dialect/HLEPGate/IR/HLEPGateDialect.td"

include "mlir/IR/EnumAttr.td"

//===----------------------------------------------------------------------===//
// Gate kinds
//===----------------------------------------------------------------------===//

def HLEPGate_GateKind : I32Enum<"GateKind", "single-qubit gate kind", [
    I32EnumCase<"X", 0, "x">,
    I32EnumCase<"Y", 1, "y">,
    I32EnumCase<"Z", 2, "z">,
    I32EnumCase<"H", 3, "h">,
    I32EnumCase<"S", 4, "s">,
    I32EnumCase<"Sdg", 5, "sdg">,
    I32EnumCase<"T", 6, "t">,
    I32EnumCase<"Tdg", 7, "tdg">,
    // Parametrized gates take one `f64` angle.
    I32EnumCase<"P", 8, "p">,
    I32EnumCase<"RX", 9, "rx">,
    I32EnumCase<"RY", 10, "ry">,
    I32EnumCase<"RZ", 11, "rz">,
]> {
  let cppNamespace = "::qcc::hlepgate";
}

def HLEPGate_GateKindAttr : EnumAttr<HLEPGateDialect, HLEPGate_GateKind, "gate_kind"> {
  let assemblyFormat = "$value";
}

#endif // INCLUDE_QCC_DIALECT_HLEPGATE_IR_HLEPGATEATTRS_TD_
