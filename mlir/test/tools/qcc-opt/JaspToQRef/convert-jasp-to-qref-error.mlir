// RUN: qcc-opt %s --convert-jasp-to-qref --split-input-file --verify-diagnostics

// `qref` has no `xxyy`, and the pass does not decompose gates.
func.func @xxyy(%q0: !jasp.Qubit, %q1: !jasp.Qubit, %a: tensor<f64>, %s0: !jasp.QuantumState) -> !jasp.QuantumState {
  // expected-error @+1 {{'jasp.quantum_gate' op applies gate 'xxyy', which convert-jasp-to-qref does not support}}
  %s1 = jasp.quantum_gate "xxyy" (%q0, %q1, %a, %a), %s0
      : (!jasp.Qubit, !jasp.Qubit, tensor<f64>, tensor<f64>), !jasp.QuantumState -> !jasp.QuantumState
  return %s1 : !jasp.QuantumState
}

// -----

func.func @operands(%q0: !jasp.Qubit, %s0: !jasp.QuantumState) -> !jasp.QuantumState {
  // expected-error @+1 {{'jasp.quantum_gate' op applies gate 'cx' to 1 operands, but convert-jasp-to-qref expects 2 qubits followed by 0 angles}}
  %s1 = jasp.quantum_gate "cx" (%q0), %s0 : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
  return %s1 : !jasp.QuantumState
}

// -----

func.func @slice(%q: !jasp.QubitArray, %a: tensor<i64>, %b: tensor<i64>) -> !jasp.QubitArray {
  // expected-error @+1 {{'jasp.slice' op is not supported by convert-jasp-to-qref}}
  %r = jasp.slice %q, %a, %b : !jasp.QubitArray, tensor<i64>, tensor<i64> -> !jasp.QubitArray
  return %r : !jasp.QubitArray
}
