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

// Global gates act on all lanes of a qubit vector jointly. Their parameters are not lane-aligned vectors but a matrix
// over the lanes (see `qvec.global`), so they carry no arity here.
def QVec_GlobalGateKind : I32Enum<"GlobalGateKind", "global gate kind", [
    // C++ name, id, IR name
    I32EnumCase<"ZZ", 0, "zz">,
]> {
  let cppNamespace = "::qcc::qvec";
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECENUMS_TD_
