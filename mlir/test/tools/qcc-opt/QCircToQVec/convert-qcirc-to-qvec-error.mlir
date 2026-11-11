// RUN: qcc-opt %s --convert-qcirc-to-qvec --verify-diagnostics

func.func @scf_if(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'scf.if' op uses qubits, but convert-qcirc-to-qvec expects only 'qcc.static', 'qcirc' and 'qcf' ops to use qubits}}
  %q = scf.if %cond -> !qcc.qubit {
    scf.yield %q0 : !qcc.qubit
  } else {
    scf.yield %q1 : !qcc.qubit
  }
  return
}
