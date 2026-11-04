// RUN: qcc-opt %s -convert-qco-to-qvec --split-input-file --verify-diagnostics

// CCX acts on 3 qubits.
func.func @two_controls() {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %q2 = qco.static 2 : !qco.qubit
  // expected-error @+1 {{failed to legalize operation 'qco.ctrl' that was explicitly marked illegal}}
  %c:2, %t = qco.ctrl(%q0, %q1) targets(%a = %q2) {
    %a1 = qco.x %a : !qco.qubit -> !qco.qubit
    qco.yield %a1 : !qco.qubit
  } : ({!qco.qubit, !qco.qubit}, {!qco.qubit}) -> ({!qco.qubit, !qco.qubit}, {!qco.qubit})
  func.return
}

// -----

// CSWAP acts on 3 qubits.
func.func @unsupported_ctrl_body() {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %q2 = qco.static 2 : !qco.qubit
  // expected-error @+1 {{failed to legalize operation 'qco.ctrl' that was explicitly marked illegal}}
  %c, %t:2 = qco.ctrl(%q0) targets(%a0 = %q1, %a1 = %q2) {
    %b0, %b1 = qco.swap %a0, %a1 : !qco.qubit, !qco.qubit -> !qco.qubit, !qco.qubit
    qco.yield %b0, %b1 : !qco.qubit, !qco.qubit
  } : ({!qco.qubit}, {!qco.qubit, !qco.qubit}) -> ({!qco.qubit}, {!qco.qubit, !qco.qubit})
  func.return
}

// -----

// A controlled rz is not a cp (they differ by a relative phase), and the pass has no pattern for crz.
func.func @controlled_rz() {
  %theta = arith.constant 0.5 : f64
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  // expected-error @+1 {{failed to legalize operation 'qco.ctrl' that was explicitly marked illegal}}
  %c, %t = qco.ctrl(%q0) targets(%a = %q1) {
    %a1 = qco.rz(%theta) %a : !qco.qubit -> !qco.qubit
    qco.yield %a1 : !qco.qubit
  } : ({!qco.qubit}, {!qco.qubit}) -> ({!qco.qubit}, {!qco.qubit})
  func.return
}

// -----

// Two gates in one control body do not map to a single pair gate.
func.func @two_gates_in_ctrl_body() {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  // expected-error @+1 {{failed to legalize operation 'qco.ctrl' that was explicitly marked illegal}}
  %c, %t = qco.ctrl(%q0) targets(%a = %q1) {
    %a1 = qco.x %a : !qco.qubit -> !qco.qubit
    %a2 = qco.z %a1 : !qco.qubit -> !qco.qubit
    qco.yield %a2 : !qco.qubit
  } : ({!qco.qubit}, {!qco.qubit}) -> ({!qco.qubit}, {!qco.qubit})
  func.return
}

// -----

// The pass has no pattern for the general u gate (u_zyz).
func.func @u_gate() {
  %theta = arith.constant 0.5 : f64
  %q0 = qco.static 0 : !qco.qubit
  // expected-error @+1 {{failed to legalize operation 'qco.u' that was explicitly marked illegal}}
  %u = qco.u(%theta, %theta, %theta) %q0 : !qco.qubit -> !qco.qubit
  func.return
}

// -----

// The `scf.if` would use the qubit in both branches, but a `qcc.static` hands out each qubit only once.
func.func @if_binds_static(%cond: i1) {
  %q0 = qco.static 0 : !qco.qubit
  // expected-error @+1 {{'qco.if' op binds qubit 0 straight from its `qco.static`, which convert-qco-to-qvec does not support}}
  %q1 = qco.if %cond args(%a0 = %q0) -> (!qco.qubit) {
    %x = qco.x %a0 : !qco.qubit -> !qco.qubit
    qco.yield %x : !qco.qubit
  } else args(%a0 = %q0) {
    qco.yield %a0 : !qco.qubit
  }
  func.return
}

// -----

// A `qcc.static` takes each index once.
func.func @static_twice() {
  %q0 = qco.static 0 : !qco.qubit
  %h = qco.h %q0 : !qco.qubit -> !qco.qubit
  qco.sink %h : !qco.qubit
  // expected-error @+1 {{'qco.static' op refers to qubit 0 a second time, which convert-qco-to-qvec does not support}}
  %again = qco.static 0 : !qco.qubit
  %x = qco.x %again : !qco.qubit -> !qco.qubit
  func.return
}

// -----

// Qubits come from `qcc.static`, never from function arguments.
// expected-error @+1 {{'func.func' op takes or returns qubits, which convert-qco-to-qvec does not support}}
func.func @qubit_argument(%q: !qco.qubit) {
  %h = qco.h %q : !qco.qubit -> !qco.qubit
  func.return
}
