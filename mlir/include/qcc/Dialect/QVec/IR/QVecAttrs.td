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

// The body of a `switch` over the cases of `e`, one `case` per enumerant returning its `numParams`. Generated from the
// case list itself, so the arity table can never get out of sync with the enum.
class QVec_ArityCases<EnumInfo e, string enumName> {
  string result = !interleave(!foreach(c, e.enumerants,
      "    case " # enumName # "::" # c.symbol # ": return "
        # !cast<string>(!cast<QVec_GateCase>(c).numParams) # ";"), "\n");
}

def QVec_SingleGateAttr : EnumAttr<QVecDialect, QVec_SingleGate, "single_gate"> {
  let assemblyFormat = "$value";
  let extraClassDeclaration = [{
    /// Number of angle parameters a `qvec.single` of `kind` takes. Generated from the enum cases in QVecEnums.td.
    static unsigned getNumParams(::qcc::qvec::SingleGate kind) {
      switch (kind) {
}] # QVec_ArityCases<QVec_SingleGate, "::qcc::qvec::SingleGate">.result # [{
      }
      llvm_unreachable("unknown single-qubit gate kind");
    }
  }];
}

def QVec_PairGateAttr : EnumAttr<QVecDialect, QVec_PairGate, "pair_gate"> {
  let assemblyFormat = "$value";
  let extraClassDeclaration = [{
    /// Number of angle parameters a `qvec.pair` of `kind` takes. Generated from the enum cases in QVecEnums.td.
    static unsigned getNumParams(::qcc::qvec::PairGate kind) {
      switch (kind) {
}] # QVec_ArityCases<QVec_PairGate, "::qcc::qvec::PairGate">.result # [{
      }
      llvm_unreachable("unknown two-qubit gate kind");
    }
  }];
}

def QVec_GlobalGateAttr : EnumAttr<QVecDialect, QVec_GlobalGate, "global_gate"> {
  let assemblyFormat = "$value";
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECATTRS_TD_
