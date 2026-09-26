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

// The body of a `switch` over the cases of `e`.
class QVec_ArityCases<EnumInfo e, string enumName> {
  string result = !interleave(!foreach(c, e.enumerants,
      "    case " # enumName # "::" # c.symbol # ": return "
        # !cast<string>(!cast<QVec_GateCase>(c).numParams) # ";"), "\n");
}

def QVec_SingleGateKindAttr : EnumAttr<QVec_Dialect, QVec_SingleGateKind, "single_gate"> {
  let assemblyFormat = "$value";
  let extraClassDeclaration = [{
    /// Number of angle parameters a `qvec.single` of `kind` takes.
    static unsigned getNumParams(::qcc::qvec::SingleGateKind kind) {
      switch (kind) {
}] # QVec_ArityCases<QVec_SingleGateKind, "::qcc::qvec::SingleGateKind">.result # [{
      }
      llvm_unreachable("unknown single-qubit gate kind");
    }
  }];
}

def QVec_PairGateKindAttr : EnumAttr<QVec_Dialect, QVec_PairGateKind, "pair_gate"> {
  let assemblyFormat = "$value";
  let extraClassDeclaration = [{
    /// Number of angle parameters a `qvec.pair` of `kind` takes.
    static unsigned getNumParams(::qcc::qvec::PairGateKind kind) {
      switch (kind) {
}] # QVec_ArityCases<QVec_PairGateKind, "::qcc::qvec::PairGateKind">.result # [{
      }
      llvm_unreachable("unknown two-qubit gate kind");
    }
  }];
}

def QVec_GlobalGateKindAttr : EnumAttr<QVec_Dialect, QVec_GlobalGateKind, "global_gate"> {
  let assemblyFormat = "$value";
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECATTRS_TD_
