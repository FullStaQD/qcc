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
include "qcc/Dialect/QVec/IR/QVecEnums.td"

include "mlir/IR/EnumAttr.td"

//===----------------------------------------------------------------------===//
// Gate kind attributes
//===----------------------------------------------------------------------===//

def QVec_GlobalGateKindAttr : EnumAttr<QVec_Dialect, QVec_GlobalGateKind, "global_gate"> {
  let assemblyFormat = "$value";
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECATTRS_TD_
