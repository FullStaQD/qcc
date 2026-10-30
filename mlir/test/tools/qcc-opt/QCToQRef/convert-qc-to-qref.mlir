// RUN: qcc-opt %s --convert-qc-to-qref --split-input-file | FileCheck %s

// Each `qc.static` becomes a `qcc.static_ref` of its own, also for an index that another one names.
// CHECK-LABEL: func.func @static
func.func @static() {
  %q0 = qc.static 0 : !qc.qubit
  %q3 = qc.static 3 : !qc.qubit
  %again = qc.static 0 : !qc.qubit
  qc.x %q0 : !qc.qubit
  qc.x %q3 : !qc.qubit
  qc.x %again : !qc.qubit
  return
}
// CHECK:         %[[Q0:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:    %[[Q3:.*]] = qcc.static_ref [3] : !qcc.qubit_ref
// CHECK-NEXT:    %[[AGAIN:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single x %[[Q0]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single x %[[Q3]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single x %[[AGAIN]] : !qcc.qubit_ref
// CHECK-NEXT:    return

// -----

// CHECK-LABEL: func.func @single_gates
func.func @single_gates() {
  %q = qc.static 0 : !qc.qubit
  qc.x %q : !qc.qubit
  qc.y %q : !qc.qubit
  qc.z %q : !qc.qubit
  qc.h %q : !qc.qubit
  qc.s %q : !qc.qubit
  qc.sdg %q : !qc.qubit
  qc.t %q : !qc.qubit
  qc.tdg %q : !qc.qubit
  qc.sx %q : !qc.qubit
  qc.sxdg %q : !qc.qubit
  return
}
// CHECK:         %[[Q:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single x %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single y %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single z %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single h %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single s %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single sdg %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single t %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single tdg %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single sx %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single sxdg %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:    return

// -----

// `p` is `rz` up to a global phase. `u(theta, phi, lambda)` is `rz(phi) * ry(theta) * rz(lambda)` up to a global phase,
// which is `u_zyz(lambda, theta, phi)`.
// CHECK-LABEL: func.func @rotations
// CHECK-SAME:  (%[[THETA:.*]]: f64, %[[PHI:.*]]: f64, %[[LAMBDA:.*]]: f64)
func.func @rotations(%theta: f64, %phi: f64, %lambda: f64) {
  %q = qc.static 0 : !qc.qubit
  qc.rx(%theta) %q : !qc.qubit
  qc.ry(%theta) %q : !qc.qubit
  qc.rz(%theta) %q : !qc.qubit
  qc.p(%theta) %q : !qc.qubit
  qc.u(%theta, %phi, %lambda) %q : !qc.qubit
  return
}
// CHECK:         %[[Q:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single rx(%[[THETA]]) %[[Q]] : f64, !qcc.qubit_ref
// CHECK-NEXT:    qref.single ry(%[[THETA]]) %[[Q]] : f64, !qcc.qubit_ref
// CHECK-NEXT:    qref.single rz(%[[THETA]]) %[[Q]] : f64, !qcc.qubit_ref
// CHECK-NEXT:    qref.single rz(%[[THETA]]) %[[Q]] : f64, !qcc.qubit_ref
// CHECK-NEXT:    qref.single u_zyz(%[[LAMBDA]], %[[THETA]], %[[PHI]]) %[[Q]] : f64, !qcc.qubit_ref
// CHECK-NEXT:    return

// -----

// CHECK-LABEL: func.func @pair_gates
// CHECK-SAME:  (%[[THETA:.*]]: f64)
func.func @pair_gates(%theta: f64) {
  %q0 = qc.static 0 : !qc.qubit
  %q1 = qc.static 1 : !qc.qubit
  qc.swap %q0, %q1 : !qc.qubit, !qc.qubit
  qc.iswap %q1, %q0 : !qc.qubit, !qc.qubit
  qc.rxx(%theta) %q0, %q1 : !qc.qubit, !qc.qubit
  qc.ryy(%theta) %q0, %q1 : !qc.qubit, !qc.qubit
  qc.rzz(%theta) %q0, %q1 : !qc.qubit, !qc.qubit
  return
}
// CHECK:         %[[Q0:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:    %[[Q1:.*]] = qcc.static_ref [1] : !qcc.qubit_ref
// CHECK-NEXT:    qref.pair swap %[[Q0]], %[[Q1]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.pair iswap %[[Q1]], %[[Q0]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.pair rxx(%[[THETA]]) %[[Q0]], %[[Q1]] : f64, !qcc.qubit_ref
// CHECK-NEXT:    qref.pair ryy(%[[THETA]]) %[[Q0]], %[[Q1]] : f64, !qcc.qubit_ref
// CHECK-NEXT:    qref.pair rzz(%[[THETA]]) %[[Q0]], %[[Q1]] : f64, !qcc.qubit_ref
// CHECK-NEXT:    return

// -----

// One control around a single gate: the control becomes `lhs`. A controlled global phase is a phase on the control.
// CHECK-LABEL: func.func @controlled_gates
// CHECK-SAME:  (%[[THETA:.*]]: f64)
func.func @controlled_gates(%theta: f64) {
  %c = qc.static 0 : !qc.qubit
  %t = qc.static 1 : !qc.qubit
  qc.ctrl(%c) targets (%a = %t) {
    qc.x %a : !qc.qubit
    qc.yield
  } : {!qc.qubit}, {!qc.qubit}
  qc.ctrl(%c) targets (%a = %t) {
    qc.y %a : !qc.qubit
    qc.yield
  } : {!qc.qubit}, {!qc.qubit}
  qc.ctrl(%t) targets (%a = %c) {
    qc.z %a : !qc.qubit
    qc.yield
  } : {!qc.qubit}, {!qc.qubit}
  qc.ctrl(%c) targets (%a = %t) {
    qc.p(%theta) %a : !qc.qubit
    qc.yield
  } : {!qc.qubit}, {!qc.qubit}
  qc.ctrl(%c) targets (%a = %t) {
    qc.rz(%theta) %a : !qc.qubit
    qc.yield
  } : {!qc.qubit}, {!qc.qubit}
  qc.ctrl(%t) targets () {
    qc.gphase(%theta)
    qc.yield
  } : {!qc.qubit}
  return
}
// CHECK:         %[[C:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:    %[[T:.*]] = qcc.static_ref [1] : !qcc.qubit_ref
// CHECK-NEXT:    qref.pair cx %[[C]], %[[T]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.pair cy %[[C]], %[[T]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.pair cz %[[T]], %[[C]] : !qcc.qubit_ref
// CHECK-NEXT:    qref.pair cp(%[[THETA]]) %[[C]], %[[T]] : f64, !qcc.qubit_ref
// CHECK-NEXT:    qref.pair crz(%[[THETA]]) %[[C]], %[[T]] : f64, !qcc.qubit_ref
// CHECK-NEXT:    qref.single rz(%[[THETA]]) %[[T]] : f64, !qcc.qubit_ref
// CHECK-NEXT:    return

// -----

// Up to a global phase, `id` and `gphase` do nothing: references need no op to pass a qubit on.
// CHECK-LABEL: func.func @dropped
func.func @dropped(%theta: f64) {
  %q = qc.static 0 : !qc.qubit
  qc.id %q : !qc.qubit
  qc.gphase(%theta)
  return
}
// CHECK-NEXT:    qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:    return

// -----

// CHECK-LABEL: func.func @measure_and_reset
func.func @measure_and_reset() -> i1 {
  %q = qc.static 0 : !qc.qubit
  qc.reset %q : !qc.qubit
  %bit = qc.measure %q : !qc.qubit -> i1
  return %bit : i1
}
// CHECK:         %[[Q:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:    qref.reset z %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:    %[[BIT:.*]] = qref.measure z %[[Q]] : !qcc.qubit_ref -> i1
// CHECK-NEXT:    return %[[BIT]] : i1

// -----

// Ops on references need no special treatment in standard control flow.
// CHECK-LABEL: func.func @control_flow
func.func @control_flow() -> i1 {
  %q0 = qc.static 0 : !qc.qubit
  %q1 = qc.static 1 : !qc.qubit
  %bit = qc.measure %q0 : !qc.qubit -> i1
  scf.if %bit {
    qc.x %q1 : !qc.qubit
  }
  %m = qc.measure %q1 : !qc.qubit -> i1
  return %m : i1
}
// CHECK:         %[[Q0:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:    %[[Q1:.*]] = qcc.static_ref [1] : !qcc.qubit_ref
// CHECK-NEXT:    %[[BIT:.*]] = qref.measure z %[[Q0]] : !qcc.qubit_ref -> i1
// CHECK-NEXT:    scf.if %[[BIT]] {
// CHECK-NEXT:      qref.single x %[[Q1]] : !qcc.qubit_ref
// CHECK-NEXT:    }
// CHECK-NEXT:    %[[M:.*]] = qref.measure z %[[Q1]] : !qcc.qubit_ref -> i1
// CHECK-NEXT:    return %[[M]] : i1
