// RUN: qcc-opt %s --qcc-attach-device=file=%S/../Dialect/Qcc/Inputs/device-2x3.mlir --convert-qvec-to-magic --split-input-file --verify-diagnostics

// The device holds four ions, 0 and 1 in trap 0, 2 and 3 in trap 1.

func.func @dynamic_angle(%t: vector<4xf64>) {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %q2 = qco.static 2 : !qco.qubit
  %q3 = qco.static 3 : !qco.qubit
  %v = vector.from_elements %q0, %q1, %q2, %q3 : vector<4x!qco.qubit>
  // expected-error @+1 {{angles must be compile-time constants}}
  %l = qvec.single rz(%t) %v : vector<4x!qco.qubit>, vector<4xf64>
  %o, %r = qvec.mz %l : vector<4x!qco.qubit> -> vector<4xi1>
  %r0 = vector.extract %r[0] : i1 from vector<4xi1>
  %r1 = vector.extract %r[1] : i1 from vector<4xi1>
  %r2 = vector.extract %r[2] : i1 from vector<4xi1>
  %r3 = vector.extract %r[3] : i1 from vector<4xi1>
  aux.record_int %r0 : i1
  aux.record_int %r1 : i1
  aux.record_int %r2 : i1
  aux.record_int %r3 : i1
  return
}

// -----

func.func @too_many_qubits() {
  // expected-error @+1 {{uses qubit 4, but the device holds only 4 ions}}
  %q4 = qco.static 4 : !qco.qubit
  %v = vector.from_elements %q4 : vector<1x!qco.qubit>
  %o, %r = qvec.mz %v : vector<1x!qco.qubit> -> vector<1xi1>
  return
}

// -----

func.func @dynamic_allocation() {
  // expected-error @+1 {{is not supported: ions are placed statically, use `qco.static`}}
  %q = qco.alloc : !qco.qubit
  %v = vector.from_elements %q : vector<1x!qco.qubit>
  %o, %r = qvec.mz %v : vector<1x!qco.qubit> -> vector<1xi1>
  return
}

// -----

func.func @unrecorded_measurement() {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %q2 = qco.static 2 : !qco.qubit
  %q3 = qco.static 3 : !qco.qubit
  %v = vector.from_elements %q0, %q1, %q2, %q3 : vector<4x!qco.qubit>
  // expected-error @+1 {{must have the result of qubit 1 recorded by exactly one `aux.record_int` and used nowhere else}}
  %o, %r = qvec.mz %v : vector<4x!qco.qubit> -> vector<4xi1>
  %r0 = vector.extract %r[0] : i1 from vector<4xi1>
  %r1 = vector.extract %r[1] : i1 from vector<4xi1>
  %r2 = vector.extract %r[2] : i1 from vector<4xi1>
  %r3 = vector.extract %r[3] : i1 from vector<4xi1>
  aux.record_int %r0 : i1
  aux.record_int %r2 : i1
  aux.record_int %r3 : i1
  return
}

// -----

// Every ion of the device is measured, so a program uses all of them.
// expected-error @+1 {{does not measure qubit 3: every ion of the device (4) is measured exactly once}}
func.func @unmeasured_qubit() {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %q2 = qco.static 2 : !qco.qubit
  %v = vector.from_elements %q0, %q1, %q2 : vector<3x!qco.qubit>
  %o, %r = qvec.mz %v : vector<3x!qco.qubit> -> vector<3xi1>
  %r0 = vector.extract %r[0] : i1 from vector<3xi1>
  %r1 = vector.extract %r[1] : i1 from vector<3xi1>
  %r2 = vector.extract %r[2] : i1 from vector<3xi1>
  aux.record_int %r0 : i1
  aux.record_int %r1 : i1
  aux.record_int %r2 : i1
  return
}

// -----

func.func @gate_after_measurement() {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %q2 = qco.static 2 : !qco.qubit
  %q3 = qco.static 3 : !qco.qubit
  %v = vector.from_elements %q0, %q1, %q2, %q3 : vector<4x!qco.qubit>
  %o, %r = qvec.mz %v : vector<4x!qco.qubit> -> vector<4xi1>
  %r0 = vector.extract %r[0] : i1 from vector<4xi1>
  %r1 = vector.extract %r[1] : i1 from vector<4xi1>
  %r2 = vector.extract %r[2] : i1 from vector<4xi1>
  %r3 = vector.extract %r[3] : i1 from vector<4xi1>
  aux.record_int %r0 : i1
  aux.record_int %r1 : i1
  aux.record_int %r2 : i1
  aux.record_int %r3 : i1
  %t = arith.constant dense<0.5> : vector<4xf64>
  // expected-error @+1 {{acts after the measurement: measurements end a program}}
  %l = qvec.single rz(%t) %o : vector<4x!qco.qubit>, vector<4xf64>
  return
}

// -----

func.func @layer_order() {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %q2 = qco.static 2 : !qco.qubit
  %q3 = qco.static 3 : !qco.qubit
  %v = vector.from_elements %q0, %q1, %q2, %q3 : vector<4x!qco.qubit>
  %t = arith.constant dense<0.5> : vector<4xf64>
  %l0 = qvec.single u_zxz(%t, %t, %t) %v : vector<4x!qco.qubit>, vector<4xf64>
  // expected-error @+1 {{breaks the layer order expected from `qvec-layer`}}
  %l1 = qvec.single u_zxz(%t, %t, %t) %l0 : vector<4x!qco.qubit>, vector<4xf64>
  %o, %r = qvec.mz %l1 : vector<4x!qco.qubit> -> vector<4xi1>
  %r0 = vector.extract %r[0] : i1 from vector<4xi1>
  %r1 = vector.extract %r[1] : i1 from vector<4xi1>
  %r2 = vector.extract %r[2] : i1 from vector<4xi1>
  %r3 = vector.extract %r[3] : i1 from vector<4xi1>
  aux.record_int %r0 : i1
  aux.record_int %r1 : i1
  aux.record_int %r2 : i1
  aux.record_int %r3 : i1
  return
}

// -----

func.func @unsupported_gate() {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %q2 = qco.static 2 : !qco.qubit
  %q3 = qco.static 3 : !qco.qubit
  %v = vector.from_elements %q0, %q1, %q2, %q3 : vector<4x!qco.qubit>
  // expected-error @+1 {{gate 'h' is not supported, run `qvec-to-u-zxz` and `qvec-layer` first}}
  %l = qvec.single h %v : vector<4x!qco.qubit>
  %o, %r = qvec.mz %l : vector<4x!qco.qubit> -> vector<4xi1>
  %r0 = vector.extract %r[0] : i1 from vector<4xi1>
  %r1 = vector.extract %r[1] : i1 from vector<4xi1>
  %r2 = vector.extract %r[2] : i1 from vector<4xi1>
  %r3 = vector.extract %r[3] : i1 from vector<4xi1>
  aux.record_int %r0 : i1
  aux.record_int %r1 : i1
  aux.record_int %r2 : i1
  aux.record_int %r3 : i1
  return
}

// -----

func.func @classical_tail() {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %q2 = qco.static 2 : !qco.qubit
  %q3 = qco.static 3 : !qco.qubit
  %v = vector.from_elements %q0, %q1, %q2, %q3 : vector<4x!qco.qubit>
  %o, %r = qvec.mz %v : vector<4x!qco.qubit> -> vector<4xi1>
  %r0 = vector.extract %r[0] : i1 from vector<4xi1>
  %r1 = vector.extract %r[1] : i1 from vector<4xi1>
  %r2 = vector.extract %r[2] : i1 from vector<4xi1>
  %r3 = vector.extract %r[3] : i1 from vector<4xi1>
  aux.record_int %r0 : i1
  aux.record_int %r1 : i1
  aux.record_int %r2 : i1
  aux.record_int %r3 : i1
  %c1 = arith.constant 1 : i64
  // expected-error @+1 {{records a value that is not a measurement result}}
  aux.record_int %c1 : i64
  return
}
