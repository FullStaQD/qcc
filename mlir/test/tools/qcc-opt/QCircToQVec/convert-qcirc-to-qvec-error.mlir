// RUN: qcc-opt %s --convert-qcirc-to-qvec --verify-diagnostics

func.func @scf_if(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'scf.if' op is not supported by convert-qcirc-to-qvec on qubits}}
  %q = scf.if %cond -> !qcc.qubit {
    scf.yield %q0 : !qcc.qubit
  } else {
    scf.yield %q1 : !qcc.qubit
  }
  return
}
