// RUN: qcc-opt %s -convert-qc-to-qir --split-input-file --verify-diagnostics

/// A gate outside the supported native gate set has no QIR mapping.
func.func @unsupported_gate() attributes { qcc.entry_point } {
  %q0 = qc.static 0 : !qc.qubit
  %q1 = qc.static 1 : !qc.qubit

  // expected-error @+1 {{failed to legalize operation 'qc.swap'}}
  qc.swap %q0, %q1 : !qc.qubit, !qc.qubit

  return
}

llvm.func @__quantum__rt__initialize(!llvm.ptr)
llvm.func @__quantum__qis__x__body(!llvm.ptr)
