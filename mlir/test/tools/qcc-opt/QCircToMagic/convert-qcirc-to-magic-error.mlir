// RUN: qcc-opt %s --qcc-attach-device=file=%S/Inputs/device-2x3.mlir --convert-qcirc-to-magic --split-input-file --verify-diagnostics

// The mzd of a trap would have to come before the gate and after it: it measures all ions and ends the chain.
func.func @gate_after_measurement() {
  %q:2 = qcc.static [0, 1] : !qcc.qubit
  %a = arith.constant 0.5 : f64
  %q0, %m0 = qcirc.measure z %q#0 : !qcc.qubit -> i1
  aux.record_int %m0 : i1
  // expected-error @+1 {{acts on qubit 0 after its measurement, but convert-qcirc-to-magic expects no gate on a qubit after its measurement}}
  %a1, %b1 = qcirc.pair rzz(%a) %q#1, %q0 : f64, !qcc.qubit
  return
}

// -----

func.func @measured_twice() {
  %q = qcc.static [0] : !qcc.qubit
  %q0, %m0 = qcirc.measure z %q : !qcc.qubit -> i1
  // expected-error @+1 {{measures qubit 0 a second time, but convert-qcirc-to-magic expects no second measurement of a qubit}}
  %q1, %m1 = qcirc.measure z %q0 : !qcc.qubit -> i1
  return
}

// -----

func.func @dynamic_angle(%theta: f64) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{takes an angle that is not a compile-time constant, but convert-qcirc-to-magic expects constant angles}}
  %q0 = qcirc.single rz(%theta) %q : f64, !qcc.qubit
  return
}

// -----

// The device has two traps of capacity 3: it takes up to four qubits, two per trap.
func.func @too_many_qubits() {
  // expected-error @+1 {{uses qubit 4, but the device can be loaded with at most 4 ions: one slot per trap stays free for shuttling}}
  %q = qcc.static [4] : !qcc.qubit
  return
}

// -----

func.func @recorded_twice() {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{has its result used other than by one 'aux.record_int', which convert-qcirc-to-magic does not support}}
  %q0, %m0 = qcirc.measure z %q : !qcc.qubit -> i1
  aux.record_int %m0 : i1
  aux.record_int %m0 : i1
  return
}

// -----

func.func @single_gate() {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{applies gate 'h', but convert-qcirc-to-magic expects only 'u_zxz' and 'rz'}}
  %q0 = qcirc.single h %q : !qcc.qubit
  return
}

// -----

func.func @pair_gate() {
  %q:2 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{applies gate 'cx', but convert-qcirc-to-magic expects only 'rzz'}}
  %c, %t = qcirc.pair cx %q#0, %q#1 : !qcc.qubit
  return
}

// -----

func.func @measure_x() {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{measures in basis 'x', which convert-qcirc-to-magic does not support}}
  %q0, %m0 = qcirc.measure x %q : !qcc.qubit -> i1
  return
}

// -----

func.func @reset() {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{resets a qubit, which convert-qcirc-to-magic does not support}}
  %q0 = qcirc.reset z %q : !qcc.qubit
  return
}

// -----

func.func @if_on_qubits(%c: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{uses qubits, but convert-qcirc-to-magic expects only 'qcc.static' and 'qcirc' ops to use qubits}}
  %q0 = qcf.if %c (%a = %q) -> (!qcc.qubit) {
    %a1 = qcirc.single x %a : !qcc.qubit
    qcf.yield %a1 : !qcc.qubit
  }
  return
}

// -----

func.func @classical_record() {
  %q = qcc.static [0] : !qcc.qubit
  %c1 = arith.constant 1 : i64
  // expected-error @+1 {{records a value that is not a measurement result, which convert-qcirc-to-magic does not support}}
  aux.record_int %c1 : i64
  return
}
