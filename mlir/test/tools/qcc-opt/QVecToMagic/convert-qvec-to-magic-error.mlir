// RUN: qcc-opt %s --qcc-attach-device=file=%S/Inputs/device-2x3.mlir --convert-qvec-to-magic --split-input-file --verify-diagnostics

func.func @dynamic_angle(%t: vector<1xf64>) {
  %q0 = qcc.static [0] : !qcc.qubit
  %v = vector.from_elements %q0 : vector<1x!qcc.qubit>
  // expected-error @+1 {{angles must be compile-time constants}}
  %l = qvec.single rz(%t) %v : vector<1xf64>, vector<1x!qcc.qubit>
  %o, %r = qvec.measure z %l : vector<1x!qcc.qubit> -> vector<1xi1>
  %r0 = vector.extract %r[0] : i1 from vector<1xi1>
  aux.record_int %r0 : i1
  return
}

// -----

// The device has two traps of capacity 3: it takes up to four qubits, two per trap.
func.func @too_many_qubits() {
  // expected-error @+1 {{uses qubit 4, but the device can be loaded with at most 4 ions: one slot per trap stays free for shuttling}}
  %q4 = qcc.static [4] : !qcc.qubit
  %v = vector.from_elements %q4 : vector<1x!qcc.qubit>
  %o, %r = qvec.measure z %v : vector<1x!qcc.qubit> -> vector<1xi1>
  return
}

// -----

func.func @poison_extract() {
  %q0 = qcc.static [0] : !qcc.qubit
  %v = vector.from_elements %q0 : vector<1x!qcc.qubit>
  // expected-error @+1 {{must not extract at the poison position}}
  %a = vector.extract %v[-1] : !qcc.qubit from vector<1x!qcc.qubit>
  %o, %r = qvec.measure z %v : vector<1x!qcc.qubit> -> vector<1xi1>
  return
}

// -----

func.func @recorded_twice() {
  %q0 = qcc.static [0] : !qcc.qubit
  %v = vector.from_elements %q0 : vector<1x!qcc.qubit>
  // expected-error @+1 {{must have the result of qubit 0 recorded by at most one `aux.record_int` and used nowhere else}}
  %o, %r = qvec.measure z %v : vector<1x!qcc.qubit> -> vector<1xi1>
  %r0 = vector.extract %r[0] : i1 from vector<1xi1>
  aux.record_int %r0 : i1
  aux.record_int %r0 : i1
  return
}

// -----

func.func @gate_after_measurement() {
  %q0 = qcc.static [0] : !qcc.qubit
  %v = vector.from_elements %q0 : vector<1x!qcc.qubit>
  %o, %r = qvec.measure z %v : vector<1x!qcc.qubit> -> vector<1xi1>
  %r0 = vector.extract %r[0] : i1 from vector<1xi1>
  aux.record_int %r0 : i1
  %t = arith.constant dense<0.5> : vector<1xf64>
  // expected-error @+1 {{acts after the measurement: measurements end a program}}
  %l = qvec.single rz(%t) %o : vector<1xf64>, vector<1x!qcc.qubit>
  return
}

// -----

func.func @layer_order() {
  %q0 = qcc.static [0] : !qcc.qubit
  %v = vector.from_elements %q0 : vector<1x!qcc.qubit>
  %t = arith.constant dense<0.5> : vector<1xf64>
  %l0 = qvec.single u_zxz(%t, %t, %t) %v : vector<1xf64>, vector<1x!qcc.qubit>
  // expected-error @+1 {{breaks the layer order expected from `qvec-layer`}}
  %l1 = qvec.single u_zxz(%t, %t, %t) %l0 : vector<1xf64>, vector<1x!qcc.qubit>
  %o, %r = qvec.measure z %l1 : vector<1x!qcc.qubit> -> vector<1xi1>
  %r0 = vector.extract %r[0] : i1 from vector<1xi1>
  aux.record_int %r0 : i1
  return
}

// -----

func.func @unsupported_gate() {
  %q0 = qcc.static [0] : !qcc.qubit
  %v = vector.from_elements %q0 : vector<1x!qcc.qubit>
  // expected-error @+1 {{gate 'h' is not supported, run `qvec-to-u-zxz` and `qvec-layer` first}}
  %l = qvec.single h %v : vector<1x!qcc.qubit>
  %o, %r = qvec.measure z %l : vector<1x!qcc.qubit> -> vector<1xi1>
  %r0 = vector.extract %r[0] : i1 from vector<1xi1>
  aux.record_int %r0 : i1
  return
}

// -----

func.func @measure_x() {
  %q0 = qcc.static [0] : !qcc.qubit
  %v = vector.from_elements %q0 : vector<1x!qcc.qubit>
  // expected-error @+1 {{measures in basis 'x', which convert-qvec-to-magic does not support}}
  %o, %r = qvec.measure x %v : vector<1x!qcc.qubit> -> vector<1xi1>
  %r0 = vector.extract %r[0] : i1 from vector<1xi1>
  aux.record_int %r0 : i1
  return
}

// -----

func.func @reset() {
  %q0 = qcc.static [0] : !qcc.qubit
  %v = vector.from_elements %q0 : vector<1x!qcc.qubit>
  // expected-error @+1 {{'qvec.reset' op is not supported by convert-qvec-to-magic}}
  %o = qvec.reset z %v : vector<1x!qcc.qubit>
  return
}

// -----

func.func @classical_tail() {
  %q0 = qcc.static [0] : !qcc.qubit
  %v = vector.from_elements %q0 : vector<1x!qcc.qubit>
  %o, %r = qvec.measure z %v : vector<1x!qcc.qubit> -> vector<1xi1>
  %r0 = vector.extract %r[0] : i1 from vector<1xi1>
  aux.record_int %r0 : i1
  %c1 = arith.constant 1 : i64
  // expected-error @+1 {{records a value that is not a measurement result}}
  aux.record_int %c1 : i64
  return
}
