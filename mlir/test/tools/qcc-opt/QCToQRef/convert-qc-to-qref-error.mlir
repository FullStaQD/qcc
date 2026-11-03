// RUN: qcc-opt %s --convert-qc-to-qref --split-input-file --verify-diagnostics

// The pass does not decompose: a gate that `qref` does not have is an error.
func.func @unsupported_gate(%theta: f64) {
  %q0 = qc.static 0 : !qc.qubit
  %q1 = qc.static 1 : !qc.qubit
  // expected-error @+1 {{failed to legalize operation 'qc.xx_plus_yy' that was explicitly marked illegal}}
  qc.xx_plus_yy(%theta, %theta) %q0, %q1 : !qc.qubit, !qc.qubit
  return
}

// -----

func.func @two_controls() {
  %q0 = qc.static 0 : !qc.qubit
  %q1 = qc.static 1 : !qc.qubit
  %q2 = qc.static 2 : !qc.qubit
  // expected-error @+1 {{failed to legalize operation 'qc.ctrl' that was explicitly marked illegal}}
  qc.ctrl(%q0, %q1) targets (%a = %q2) {
    qc.x %a : !qc.qubit
    qc.yield
  } : {!qc.qubit, !qc.qubit}, {!qc.qubit}
  return
}

// -----

// `qref` has no controlled `h`.
func.func @unsupported_ctrl_body() {
  %q0 = qc.static 0 : !qc.qubit
  %q1 = qc.static 1 : !qc.qubit
  // expected-error @+1 {{failed to legalize operation 'qc.ctrl' that was explicitly marked illegal}}
  qc.ctrl(%q0) targets (%a = %q1) {
    qc.h %a : !qc.qubit
    qc.yield
  } : {!qc.qubit}, {!qc.qubit}
  return
}

// -----

// Two gates in one control body do not make one two-qubit gate.
func.func @two_gates_in_ctrl_body() {
  %q0 = qc.static 0 : !qc.qubit
  %q1 = qc.static 1 : !qc.qubit
  // expected-error @+1 {{failed to legalize operation 'qc.ctrl' that was explicitly marked illegal}}
  qc.ctrl(%q0) targets (%a = %q1) {
    qc.x %a : !qc.qubit
    qc.z %a : !qc.qubit
    qc.yield
  } : {!qc.qubit}, {!qc.qubit}
  return
}

// -----

// Only static qubits are supported.
func.func @alloc() {
  // expected-error @+1 {{failed to legalize operation 'qc.alloc' that was explicitly marked illegal}}
  %q = qc.alloc : !qc.qubit
  qc.x %q : !qc.qubit
  return
}
