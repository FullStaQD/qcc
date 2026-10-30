// RUN: qcc-opt %s --convert-qcirc-to-qref --split-input-file --verify-diagnostics

func.func @vector(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'vector.from_elements' op is not supported on vectors of qubits}}
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  %v_out = qcf.if %cond (%w = %v) -> vector<2x!qcc.qubit> {
    qcf.yield %w : vector<2x!qcc.qubit>
  }
  return
}
