// RUN: qcc-opt %s | FileCheck %s
// RUN: qcc-opt %s --mlir-print-op-generic | qcc-opt | FileCheck %s

// CHECK-LABEL: func.func @single_gates
// CHECK-SAME: (%[[A:.*]]: f64, %[[B:.*]]: f64, %[[C:.*]]: f64)
func.func @single_gates(%a: f64, %b: f64, %c: f64) {
  // CHECK: %[[Q:.*]] = qcc.static [0] : !qcc.qubit
  %q = qcc.static [0] : !qcc.qubit
  // Without parameters; these differ only in the keyword.
  // CHECK: %[[X:.*]] = qcirc.single x %[[Q]] : !qcc.qubit
  %x = qcirc.single x %q : !qcc.qubit
  // CHECK: %[[H:.*]] = qcirc.single h %[[X]] : !qcc.qubit
  %h = qcirc.single h %x : !qcc.qubit
  // CHECK: %[[SDG:.*]] = qcirc.single sdg %[[H]] : !qcc.qubit
  %sdg = qcirc.single sdg %h : !qcc.qubit
  // One parameter, whose type precedes the qubit type.
  // CHECK: %[[RZ:.*]] = qcirc.single rz(%[[A]]) %[[SDG]] : f64, !qcc.qubit
  %rz = qcirc.single rz(%a) %sdg : f64, !qcc.qubit
  // Three parameters share one type.
  // CHECK: qcirc.single u_zxz(%[[A]], %[[B]], %[[C]]) %[[RZ]] : f64, !qcc.qubit
  %zxz = qcirc.single u_zxz(%a, %b, %c) %rz : f64, !qcc.qubit
  return
}

// CHECK-LABEL: func.func @pair_gates
// CHECK-SAME: (%[[THETA:.*]]: f64)
func.func @pair_gates(%theta: f64) {
  // CHECK: %[[Q:.*]]:2 = qcc.static [0, 1] : !qcc.qubit
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // Without parameters. The operand order is kept (`lhs` is the control), and the results follow it.
  // CHECK: %[[B0:.*]], %[[A0:.*]] = qcirc.pair cx %[[Q]]#1, %[[Q]]#0 : !qcc.qubit
  %b0, %a0 = qcirc.pair cx %q1, %q0 : !qcc.qubit
  // One parameter.
  // CHECK: qcirc.pair rzz(%[[THETA]]) %[[A0]], %[[B0]] : f64, !qcc.qubit
  %a1, %b1 = qcirc.pair rzz(%theta) %a0, %b0 : f64, !qcc.qubit
  return
}

// CHECK-LABEL: func.func @measure_and_reset
func.func @measure_and_reset() -> (i1, i1) {
  // CHECK: %[[Q:.*]] = qcc.static [0] : !qcc.qubit
  %q = qcc.static [0] : !qcc.qubit
  // CHECK: %[[MZ:.*]], %[[BIT_Z:.*]] = qcirc.measure z %[[Q]] : !qcc.qubit -> i1
  %mz, %bit_z = qcirc.measure z %q : !qcc.qubit -> i1
  // CHECK: %[[RZ:.*]] = qcirc.reset z %[[MZ]] : !qcc.qubit
  %rz = qcirc.reset z %mz : !qcc.qubit
  // CHECK: %[[RX:.*]] = qcirc.reset x %[[RZ]] : !qcc.qubit
  %rx = qcirc.reset x %rz : !qcc.qubit
  // CHECK: %{{.*}}, %[[BIT_X:.*]] = qcirc.measure x %[[RX]] : !qcc.qubit -> i1
  %mx, %bit_x = qcirc.measure x %rx : !qcc.qubit -> i1
  // CHECK: return %[[BIT_Z]], %[[BIT_X]]
  return %bit_z, %bit_x : i1, i1
}
