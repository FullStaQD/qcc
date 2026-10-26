// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCC_IR_QCCATTRS_TD_
#define INCLUDE_QCC_DIALECT_QCC_IR_QCCATTRS_TD_

include "qcc/Dialect/Qcc/IR/QccDialect.td"
include "qcc/Dialect/Qcc/IR/QccEnums.td"

include "mlir/IR/EnumAttr.td"

//===----------------------------------------------------------------------===//
// Gate kind attributes
//===----------------------------------------------------------------------===//

// The body of a `switch` over the cases of `e`.
class Qcc_ArityCases<EnumInfo e, string enumName> {
  string result = !interleave(!foreach(c, e.enumerants,
      "    case " # enumName # "::" # c.symbol # ": return "
        # !cast<string>(!cast<Qcc_GateCase>(c).numParams) # ";"), "\n");
}

def Qcc_SingleGateKindAttr : EnumAttr<Qcc_Dialect, Qcc_SingleGateKind, "single_gate"> {
  let assemblyFormat = "$value";
  let extraClassDeclaration = [{
    /// Number of angle parameters a single-qubit gate of `kind` takes.
    static unsigned getNumParams(::qcc::SingleGateKind kind) {
      switch (kind) {
}] # Qcc_ArityCases<Qcc_SingleGateKind, "::qcc::SingleGateKind">.result # [{
      }
      llvm_unreachable("unknown single-qubit gate kind");
    }
  }];
}

def Qcc_PairGateKindAttr : EnumAttr<Qcc_Dialect, Qcc_PairGateKind, "pair_gate"> {
  let assemblyFormat = "$value";
  let extraClassDeclaration = [{
    /// Number of angle parameters a two-qubit gate of `kind` takes.
    static unsigned getNumParams(::qcc::PairGateKind kind) {
      switch (kind) {
}] # Qcc_ArityCases<Qcc_PairGateKind, "::qcc::PairGateKind">.result # [{
      }
      llvm_unreachable("unknown two-qubit gate kind");
    }
  }];
}

//===----------------------------------------------------------------------===//
// Basis attribute
//===----------------------------------------------------------------------===//

def Qcc_BasisAttr : EnumAttr<Qcc_Dialect, Qcc_Basis, "basis"> {
  let assemblyFormat = "$value";
}

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCATTRS_TD_
