// RUN: qcc-opt %s | FileCheck %s
// RUN: qcc-opt %s --mlir-print-op-generic | qcc-opt | FileCheck %s

// CHECK-LABEL: func.func @single_gates
func.func @single_gates() {
  // CHECK: %[[Q:.*]] = qcc.static [0] : !qcc.qubit
  %q = qcc.static [0] : !qcc.qubit
  // CHECK: %[[X:.*]] = qcirc.single x %[[Q]] : !qcc.qubit
  %x = qcirc.single x %q : !qcc.qubit
  // CHECK: %[[Y:.*]] = qcirc.single y %[[X]] : !qcc.qubit
  %y = qcirc.single y %x : !qcc.qubit
  // CHECK: %[[Z:.*]] = qcirc.single z %[[Y]] : !qcc.qubit
  %z = qcirc.single z %y : !qcc.qubit
  // CHECK: %[[H:.*]] = qcirc.single h %[[Z]] : !qcc.qubit
  %h = qcirc.single h %z : !qcc.qubit
  // CHECK: %[[S:.*]] = qcirc.single s %[[H]] : !qcc.qubit
  %s = qcirc.single s %h : !qcc.qubit
  // CHECK: %[[SDG:.*]] = qcirc.single sdg %[[S]] : !qcc.qubit
  %sdg = qcirc.single sdg %s : !qcc.qubit
  // CHECK: %[[T:.*]] = qcirc.single t %[[SDG]] : !qcc.qubit
  %t = qcirc.single t %sdg : !qcc.qubit
  // CHECK: %[[TDG:.*]] = qcirc.single tdg %[[T]] : !qcc.qubit
  %tdg = qcirc.single tdg %t : !qcc.qubit
  // CHECK: %[[SX:.*]] = qcirc.single sx %[[TDG]] : !qcc.qubit
  %sx = qcirc.single sx %tdg : !qcc.qubit
  // CHECK: qcirc.single sxdg %[[SX]] : !qcc.qubit
  %sxdg = qcirc.single sxdg %sx : !qcc.qubit
  return
}

// CHECK-LABEL: func.func @parametrised_single_gates
// CHECK-SAME: (%[[A:.*]]: f64, %[[B:.*]]: f64, %[[C:.*]]: f64)
func.func @parametrised_single_gates(%a: f64, %b: f64, %c: f64) {
  // CHECK: %[[Q:.*]] = qcc.static [0] : !qcc.qubit
  %q = qcc.static [0] : !qcc.qubit
  // CHECK: %[[RX:.*]] = qcirc.single rx(%[[A]]) %[[Q]] : !qcc.qubit, f64
  %rx = qcirc.single rx(%a) %q : !qcc.qubit, f64
  // CHECK: %[[RY:.*]] = qcirc.single ry(%[[A]]) %[[RX]] : !qcc.qubit, f64
  %ry = qcirc.single ry(%a) %rx : !qcc.qubit, f64
  // CHECK: %[[RZ:.*]] = qcirc.single rz(%[[A]]) %[[RY]] : !qcc.qubit, f64
  %rz = qcirc.single rz(%a) %ry : !qcc.qubit, f64
  // Three parameters share one type.
  // CHECK: %[[ZXZ:.*]] = qcirc.single u_zxz(%[[A]], %[[B]], %[[C]]) %[[RZ]] : !qcc.qubit, f64
  %zxz = qcirc.single u_zxz(%a, %b, %c) %rz : !qcc.qubit, f64
  // CHECK: qcirc.single u_zyz(%[[A]], %[[B]], %[[C]]) %[[ZXZ]] : !qcc.qubit, f64
  %zyz = qcirc.single u_zyz(%a, %b, %c) %zxz : !qcc.qubit, f64
  return
}

// CHECK-LABEL: func.func @pair_gates
// CHECK-SAME: (%[[THETA:.*]]: f64)
func.func @pair_gates(%theta: f64) {
  // CHECK: %[[Q:.*]]:2 = qcc.static [0, 1] : !qcc.qubit
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // CHECK: %[[A0:.*]], %[[B0:.*]] = qcirc.pair cx %[[Q]]#0, %[[Q]]#1 : !qcc.qubit
  %a0, %b0 = qcirc.pair cx %q0, %q1 : !qcc.qubit
  // CHECK: %[[A1:.*]], %[[B1:.*]] = qcirc.pair cy %[[A0]], %[[B0]] : !qcc.qubit
  %a1, %b1 = qcirc.pair cy %a0, %b0 : !qcc.qubit
  // CHECK: %[[A2:.*]], %[[B2:.*]] = qcirc.pair cz %[[A1]], %[[B1]] : !qcc.qubit
  %a2, %b2 = qcirc.pair cz %a1, %b1 : !qcc.qubit
  // A swap exchanges the states, not the lanes: the operands may come in either order.
  // CHECK: %[[B3:.*]], %[[A3:.*]] = qcirc.pair swap %[[B2]], %[[A2]] : !qcc.qubit
  %b3, %a3 = qcirc.pair swap %b2, %a2 : !qcc.qubit
  // CHECK: %[[A4:.*]], %[[B4:.*]] = qcirc.pair iswap %[[A3]], %[[B3]] : !qcc.qubit
  %a4, %b4 = qcirc.pair iswap %a3, %b3 : !qcc.qubit
  // CHECK: %[[A5:.*]], %[[B5:.*]] = qcirc.pair cp(%[[THETA]]) %[[A4]], %[[B4]] : !qcc.qubit, f64
  %a5, %b5 = qcirc.pair cp(%theta) %a4, %b4 : !qcc.qubit, f64
  // CHECK: %[[A6:.*]], %[[B6:.*]] = qcirc.pair crz(%[[THETA]]) %[[A5]], %[[B5]] : !qcc.qubit, f64
  %a6, %b6 = qcirc.pair crz(%theta) %a5, %b5 : !qcc.qubit, f64
  // CHECK: %[[A7:.*]], %[[B7:.*]] = qcirc.pair rxx(%[[THETA]]) %[[A6]], %[[B6]] : !qcc.qubit, f64
  %a7, %b7 = qcirc.pair rxx(%theta) %a6, %b6 : !qcc.qubit, f64
  // CHECK: %[[A8:.*]], %[[B8:.*]] = qcirc.pair ryy(%[[THETA]]) %[[A7]], %[[B7]] : !qcc.qubit, f64
  %a8, %b8 = qcirc.pair ryy(%theta) %a7, %b7 : !qcc.qubit, f64
  // CHECK: qcirc.pair rzz(%[[THETA]]) %[[A8]], %[[B8]] : !qcc.qubit, f64
  %a9, %b9 = qcirc.pair rzz(%theta) %a8, %b8 : !qcc.qubit, f64
  return
}

// CHECK-LABEL: func.func @global_gates
// CHECK-SAME: (%[[ANGLES:.*]]: tensor<3x3xf64>)
func.func @global_gates(%angles: tensor<3x3xf64>) {
  // CHECK: %[[Q:.*]]:3 = qcc.static [0, 1, 2] : !qcc.qubit
  %q0, %q1, %q2 = qcc.static [0, 1, 2] : !qcc.qubit
  // CHECK: %[[G:.*]]:3 = qcirc.global zz(%[[ANGLES]]) %[[Q]]#0, %[[Q]]#1, %[[Q]]#2 : !qcc.qubit, tensor<3x3xf64>
  %a, %b, %c = qcirc.global zz(%angles) %q0, %q1, %q2 : !qcc.qubit, tensor<3x3xf64>
  // A constant matrix must be symmetric with a zero diagonal. The gate may act on a subset of the qubits.
  // CHECK: %[[CST:.*]] = arith.constant dense<{{\[\[}}0.000000e+00, 5.000000e-01], [5.000000e-01, 0.000000e+00]]> : tensor<2x2xf64>
  %cst = arith.constant dense<[[0.0, 0.5], [0.5, 0.0]]> : tensor<2x2xf64>
  // CHECK: qcirc.global zz(%[[CST]]) %[[G]]#2, %[[G]]#0 : !qcc.qubit, tensor<2x2xf64>
  %c1, %a1 = qcirc.global zz(%cst) %c, %a : !qcc.qubit, tensor<2x2xf64>
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
