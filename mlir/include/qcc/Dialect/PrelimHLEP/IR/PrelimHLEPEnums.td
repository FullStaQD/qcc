// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPENUMS_TD_
#define INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPENUMS_TD_

include "mlir/IR/EnumAttr.td"

//===----------------------------------------------------------------------===//
// Normal-form shapes of `prelimhlep.lin`
//
// See mlir/docs/Dialects/PrelimHLEP.md, section "Normal form of `lin` ops".
//===----------------------------------------------------------------------===//

def PrelimHLEP_LinShape : I32Enum<"LinShape", "normal-form shape of a `prelimhlep.lin` op", [
    I32EnumCase<"Alloc", 0, "alloc">,
    I32EnumCase<"Split", 1, "split">,
    I32EnumCase<"Join", 2, "join">,
    I32EnumCase<"X", 3, "x">,
    I32EnumCase<"Measure", 4, "measure">,
    I32EnumCase<"MeasureDrop", 5, "measure_drop">,
    I32EnumCase<"Hadamard", 6, "hadamard">,
    I32EnumCase<"Phase", 7, "phase">,
    I32EnumCase<"Ctrl", 8, "ctrl">,
]> {
  let cppNamespace = "::qcc::prelimhlep";
}

#endif // INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPENUMS_TD_
