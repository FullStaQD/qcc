// RUN: qcc-opt %s -convert-qco-to-hisepq --split-input-file --verify-diagnostics

// CCX acts on 3 qubits.
func.func @two_controls() {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %q2 = qco.static 2 : !qco.qubit
  // expected-error @+1 {{failed to legalize operation 'qco.ctrl' that was explicitly marked illegal}}
  %c:2, %t = qco.ctrl(%q0, %q1) targets(%a = %q2) {
    %a1 = qco.x %a : !qco.qubit -> !qco.qubit
    qco.yield %a1
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
    qco.yield %b0, %b1
  } : ({!qco.qubit}, {!qco.qubit, !qco.qubit}) -> ({!qco.qubit}, {!qco.qubit, !qco.qubit})
  func.return
}
