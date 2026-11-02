// RUN: qcc-opt %s --convert-qcirc-to-qref --verify-diagnostics

func.func @vector() {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'vector.from_elements' op uses a vector of qubits, which convert-qcirc-to-qref does not support}}
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  return
}
