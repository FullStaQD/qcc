// RUN: qcc-opt %s --qcc-attach-device=file=%S/Inputs/device-2x3.mlir --convert-qcirc-to-magic --split-input-file | FileCheck %s

// Two traps of capacity 3, each takes two ions: qubits 0, 1 are ions 0, 1 in trap 0, qubits 2, 3 are ions 2, 3 in
// trap 1. Each gate becomes one magic op on the chain of its trap, in program order: an rzz within a trap an
// active_zz, one across traps an inter_trap_zz with the lower ion first. Each trap is measured once, behind all gates.
// The records keep their order: q2, q3, q0, q1.
// CHECK-LABEL: func.func @two_traps
func.func @two_traps() attributes {qcc.entry_point} {
  %q:4 = qcc.static [0, 1, 2, 3] : !qcc.qubit
  %a = arith.constant 0.5 : f64
  %b = arith.constant 0.25 : f64
  %q0, %q1 = qcirc.pair rzz(%a) %q#0, %q#1 : f64, !qcc.qubit
  %q3, %q0_1 = qcirc.pair rzz(%b) %q#3, %q0 : f64, !qcc.qubit
  %q1_1 = qcirc.single u_zxz(%a, %b, %a) %q1 : f64, !qcc.qubit
  %q3_1 = qcirc.single rz(%b) %q3 : f64, !qcc.qubit
  %q0_2, %m0 = qcirc.measure z %q0_1 : !qcc.qubit -> i1
  %q1_2, %m1 = qcirc.measure z %q1_1 : !qcc.qubit -> i1
  %q2, %m2 = qcirc.measure z %q#2 : !qcc.qubit -> i1
  %q3_2, %m3 = qcirc.measure z %q3_1 : !qcc.qubit -> i1
  aux.record_int %m2 : i1
  aux.record_int %m3 : i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init : !chain, !chain1
// CHECK-NEXT: %[[A0:.*]] = magic.active_zz %[[INIT]]#0 {angles = dense<{{\[\[}}0.000000e+00, 5.000000e-01], [5.000000e-01, 0.000000e+00]]> : tensor<2x2xf64>} : !chain
// CHECK-NEXT: %[[A1:.*]], %[[B1:.*]] = magic.inter_trap_zz %[[A0]], %[[INIT]]#1 ions [0, 3] {angle = 2.500000e-01 : f64} : !chain, !chain1
// CHECK-NEXT: %[[A2:.*]] = magic.zxz %[[A1]] ions [1] {x = [2.500000e-01], z1 = [5.000000e-01], z2 = [5.000000e-01]} : !chain
// CHECK-NEXT: %[[B2:.*]] = magic.rz %[[B1]] ions [3] {angles = [2.500000e-01]} : !chain1
// CHECK-NEXT: %[[MA:.*]]:2 = magic.mzd %[[A2]] : !chain -> i1, i1
// CHECK-NEXT: %[[MB:.*]]:2 = magic.mzd %[[B2]] : !chain1 -> i1, i1
// CHECK-NEXT: aux.record_int %[[MB]]#0 : i1
// CHECK-NEXT: aux.record_int %[[MB]]#1 : i1
// CHECK-NEXT: aux.record_int %[[MA]]#0 : i1
// CHECK-NEXT: aux.record_int %[[MA]]#1 : i1
// CHECK-NEXT: return

// -----

// A measurement does not end the program: the mzd of trap 0 goes behind the gate on qubit 1, which follows the
// measurement of qubit 0. The record stays where it is.
// CHECK-LABEL: func.func @gate_after_other_measurement
func.func @gate_after_other_measurement() {
  %q:2 = qcc.static [0, 1] : !qcc.qubit
  %a = arith.constant 0.5 : f64
  %q0, %m0 = qcirc.measure z %q#0 : !qcc.qubit -> i1
  aux.record_int %m0 : i1
  %q1 = qcirc.single rz(%a) %q#1 : f64, !qcc.qubit
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init : !chain, !chain1
// CHECK-NEXT: %[[C1:.*]] = magic.rz %[[INIT]]#0 ions [1] {angles = [5.000000e-01]} : !chain
// CHECK-NEXT: %[[M:.*]]:2 = magic.mzd %[[C1]] : !chain -> i1, i1
// CHECK-NEXT: aux.record_int %[[M]]#0 : i1
// CHECK-NEXT: return

// -----

// A program creates only as many ions as it has qubits. Three fit into trap 0, so trap 1 stays empty and is not
// measured.
// CHECK:       !chain = !magic.ion_chain<0, [0:1, 1:1, 2:1]>
// CHECK:       !chain1 = !magic.ion_chain<1, []>
// CHECK-LABEL: func.func @three_qubits
func.func @three_qubits() {
  %q:3 = qcc.static [0, 1, 2] : !qcc.qubit
  %q0, %m0 = qcirc.measure z %q#0 : !qcc.qubit -> i1
  %q1, %m1 = qcirc.measure z %q#1 : !qcc.qubit -> i1
  %q2, %m2 = qcirc.measure z %q#2 : !qcc.qubit -> i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init : !chain, !chain1
// CHECK-NEXT: magic.mzd %[[INIT]]#0 : !chain -> i1, i1, i1
// CHECK-NOT:  magic.mzd

// -----

// Measuring and recording are optional. The mzd measures its whole trap, so qubit 1 is measured without a
// `qcirc.measure`; its result stays unused. Trap 1 holds no measured qubit and gets no mzd.
// CHECK-LABEL: func.func @partly_observed
func.func @partly_observed() {
  %q:4 = qcc.static [0, 1, 2, 3] : !qcc.qubit
  %a = arith.constant 0.5 : f64
  %q0, %m0 = qcirc.measure z %q#0 : !qcc.qubit -> i1
  %q3 = qcirc.single rz(%a) %q#3 : f64, !qcc.qubit
  aux.record_int %m0 : i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init : !chain, !chain1
// CHECK-NEXT: magic.rz %[[INIT]]#1 ions [3] {angles = [5.000000e-01]} : !chain1
// CHECK-NEXT: %[[M:.*]]:2 = magic.mzd %[[INIT]]#0 : !chain -> i1, i1
// CHECK-NEXT: aux.record_int %[[M]]#0 : i1
// CHECK-NEXT: return

// -----

// A function without `qcc.static` is left alone.
// CHECK-LABEL: func.func @classical
func.func @classical(%x: i64) -> i64 {
  %c = arith.constant 1 : i64
  %y = arith.addi %x, %c : i64
  return %y : i64
}

// CHECK:      %[[C:.*]] = arith.constant 1 : i64
// CHECK-NEXT: %[[Y:.*]] = arith.addi %arg0, %[[C]] : i64
// CHECK-NEXT: return %[[Y]]
