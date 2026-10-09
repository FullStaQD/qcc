// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCIRC_IR_QCIRCATTRS_TD_
#define INCLUDE_QCC_DIALECT_QCIRC_IR_QCIRCATTRS_TD_

include "qcc/Dialect/QCirc/IR/QCircDialect.td"
include "qcc/Dialect/QCirc/IR/QCircEnums.td"

include "mlir/IR/EnumAttr.td"

//===----------------------------------------------------------------------===//
// Gate kind attributes
//===----------------------------------------------------------------------===//

// The body of a `switch` over the cases of `e`.
class QCirc_ArityCases<EnumInfo e, string enumName> {
  string result = !interleave(!foreach(c, e.enumerants,
      "    case " # enumName # "::" # c.symbol # ": return "
        # !cast<string>(!cast<QCirc_GateCase>(c).numParams) # ";"), "\n");
}

def QCirc_SingleGateKindAttr : EnumAttr<QCirc_Dialect, QCirc_SingleGateKind, "single_gate"> {
  let assemblyFormat = "$value";
  let extraClassDeclaration = [{
    /// Number of angle parameters a `qcirc.single` of `kind` takes.
    static unsigned getNumParams(::qcc::qcirc::SingleGateKind kind) {
      switch (kind) {
}] # QCirc_ArityCases<QCirc_SingleGateKind, "::qcc::qcirc::SingleGateKind">.result # [{
      }
      llvm_unreachable("unknown single-qubit gate kind");
    }
  }];
}

def QCirc_PairGateKindAttr : EnumAttr<QCirc_Dialect, QCirc_PairGateKind, "pair_gate"> {
  let assemblyFormat = "$value";
  let extraClassDeclaration = [{
    /// Number of angle parameters a `qcirc.pair` of `kind` takes.
    static unsigned getNumParams(::qcc::qcirc::PairGateKind kind) {
      switch (kind) {
}] # QCirc_ArityCases<QCirc_PairGateKind, "::qcc::qcirc::PairGateKind">.result # [{
      }
      llvm_unreachable("unknown two-qubit gate kind");
    }
  }];
}

def QCirc_GlobalGateKindAttr : EnumAttr<QCirc_Dialect, QCirc_GlobalGateKind, "global_gate"> {
  let assemblyFormat = "$value";
}

//===----------------------------------------------------------------------===//
// Basis attribute
//===----------------------------------------------------------------------===//

def QCirc_BasisAttr : EnumAttr<QCirc_Dialect, QCirc_Basis, "basis"> {
  let assemblyFormat = "$value";
}

#endif // INCLUDE_QCC_DIALECT_QCIRC_IR_QCIRCATTRS_TD_
