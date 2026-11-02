// RUN: qcc-opt %s --convert-qcirc-to-qref --split-input-file --verify-diagnostics

func.func @vector() {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'vector.from_elements' op uses a vector of qubits, which convert-qcirc-to-qref does not support}}
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  return
}

// -----

func.func @scf_if(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'scf.if' op is not supported by convert-qcirc-to-qref on qubits}}
  %q = scf.if %cond -> !qcc.qubit {
    scf.yield %q0 : !qcc.qubit
  } else {
    scf.yield %q1 : !qcc.qubit
  }
  return
}
