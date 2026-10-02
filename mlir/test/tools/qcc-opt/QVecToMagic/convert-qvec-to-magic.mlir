// RUN: qcc-opt %s --qcc-attach-device=file=%S/../Dialect/Qcc/Inputs/device-2x3.mlir --convert-qvec-to-magic --split-input-file | FileCheck %s

// Two traps of capacity 3, each takes two ions: qubits 0, 1 are ions 0, 1 in trap 0, qubits 2, 3 are ions 2, 3 in
// trap 1. A zz block spanning both traps splits into one active_zz per trap and one inter_trap_zz per coupling across.
// The records keep their order: q2, q3, q0, q1.
// CHECK-LABEL: func.func @spanning_block
func.func @spanning_block() attributes {qcc.entry_point} {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %q2 = qco.static 2 : !qco.qubit
  %q3 = qco.static 3 : !qco.qubit
  %v0 = vector.from_elements %q0, %q1, %q2, %q3 : vector<4x!qco.qubit>
  %A = arith.constant dense<[[0.0, 0.5, 0.75, 0.0], [0.5, 0.0, 0.0, -0.125], [0.75, 0.0, 0.0, 0.25], [0.0, -0.125, 0.25, 0.0]]> : vector<4x4xf64>
  %l0 = qvec.global zz(%A) %v0 : vector<4x!qco.qubit>, vector<4x4xf64>
  %a0 = vector.extract %l0[0] : !qco.qubit from vector<4x!qco.qubit>
  %a1 = vector.extract %l0[1] : !qco.qubit from vector<4x!qco.qubit>
  %a2 = vector.extract %l0[2] : !qco.qubit from vector<4x!qco.qubit>
  %a3 = vector.extract %l0[3] : !qco.qubit from vector<4x!qco.qubit>
  %v1 = vector.from_elements %a1, %a2 : vector<2x!qco.qubit>
  %z1 = arith.constant dense<[0.1, 0.2]> : vector<2xf64>
  %x = arith.constant dense<[0.3, 0.4]> : vector<2xf64>
  %z2 = arith.constant dense<[0.5, 0.6]> : vector<2xf64>
  %l1 = qvec.single u_zxz(%z1, %x, %z2) %v1 : vector<2x!qco.qubit>, vector<2xf64>
  %b1 = vector.extract %l1[0] : !qco.qubit from vector<2x!qco.qubit>
  %b2 = vector.extract %l1[1] : !qco.qubit from vector<2x!qco.qubit>
  %v2 = vector.from_elements %a0, %a3 : vector<2x!qco.qubit>
  %t = arith.constant dense<[0.7, 0.8]> : vector<2xf64>
  %l2 = qvec.single rz(%t) %v2 : vector<2x!qco.qubit>, vector<2xf64>
  %c0 = vector.extract %l2[0] : !qco.qubit from vector<2x!qco.qubit>
  %c3 = vector.extract %l2[1] : !qco.qubit from vector<2x!qco.qubit>
  %m0 = vector.from_elements %c3, %b2 : vector<2x!qco.qubit>
  %o0, %r0 = qvec.mz %m0 : vector<2x!qco.qubit> -> vector<2xi1>
  %m1 = vector.from_elements %b1, %c0 : vector<2x!qco.qubit>
  %o1, %r1 = qvec.mz %m1 : vector<2x!qco.qubit> -> vector<2xi1>
  %r3 = vector.extract %r0[0] : i1 from vector<2xi1>
  %r2 = vector.extract %r0[1] : i1 from vector<2xi1>
  %r1b = vector.extract %r1[0] : i1 from vector<2xi1>
  %r0b = vector.extract %r1[1] : i1 from vector<2xi1>
  aux.record_int %r2 : i1
  aux.record_int %r3 : i1
  aux.record_int %r0b : i1
  aux.record_int %r1b : i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init : !chain, !chain1
// CHECK-NEXT: %[[A0:.*]] = magic.active_zz %[[INIT]]#0 {angles = dense<{{\[\[}}0.000000e+00, 5.000000e-01], [5.000000e-01, 0.000000e+00]]> : tensor<2x2xf64>} : !chain
// CHECK-NEXT: %[[B0:.*]] = magic.active_zz %[[INIT]]#1 {angles = dense<{{\[\[}}0.000000e+00, 2.500000e-01], [2.500000e-01, 0.000000e+00]]> : tensor<2x2xf64>} : !chain1
// CHECK-NEXT: %[[A1:.*]], %[[B1:.*]] = magic.inter_trap_zz %[[A0]], %[[B0]] ions [0, 2] {angle = 7.500000e-01 : f64} : !chain, !chain1
// CHECK-NEXT: %[[A2:.*]], %[[B2:.*]] = magic.inter_trap_zz %[[A1]], %[[B1]] ions [1, 3] {angle = -1.250000e-01 : f64} : !chain, !chain1
// CHECK-NEXT: %[[A3:.*]] = magic.zxz %[[A2]] ions [1] {x = [3.000000e-01], z1 = [1.000000e-01], z2 = [5.000000e-01]} : !chain
// CHECK-NEXT: %[[B3:.*]] = magic.zxz %[[B2]] ions [2] {x = [4.000000e-01], z1 = [2.000000e-01], z2 = [6.000000e-01]} : !chain1
// CHECK-NEXT: %[[A4:.*]] = magic.rz %[[A3]] ions [0] {angles = [0.69999999999999996]} : !chain
// CHECK-NEXT: %[[B4:.*]] = magic.rz %[[B3]] ions [3] {angles = [8.000000e-01]} : !chain1
// CHECK-NEXT: %[[MA:.*]]:2 = magic.mzd %[[A4]] : !chain -> i1, i1
// CHECK-NEXT: %[[MB:.*]]:2 = magic.mzd %[[B4]] : !chain1 -> i1, i1
// CHECK-NEXT: aux.record_int %[[MB]]#0 : i1
// CHECK-NEXT: aux.record_int %[[MB]]#1 : i1
// CHECK-NEXT: aux.record_int %[[MA]]#0 : i1
// CHECK-NEXT: aux.record_int %[[MA]]#1 : i1
// CHECK-NEXT: return

// -----

// A layer over both traps becomes one op per trap; a zz block within one trap only touches that trap.
// CHECK-LABEL: func.func @one_op_per_trap
func.func @one_op_per_trap() {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %q2 = qco.static 2 : !qco.qubit
  %q3 = qco.static 3 : !qco.qubit
  %v0 = vector.from_elements %q0, %q1, %q2, %q3 : vector<4x!qco.qubit>
  %h = arith.constant dense<1.5707963267948966> : vector<4xf64>
  %l0 = qvec.single u_zxz(%h, %h, %h) %v0 : vector<4x!qco.qubit>, vector<4xf64>
  %a0 = vector.extract %l0[0] : !qco.qubit from vector<4x!qco.qubit>
  %a1 = vector.extract %l0[1] : !qco.qubit from vector<4x!qco.qubit>
  %a2 = vector.extract %l0[2] : !qco.qubit from vector<4x!qco.qubit>
  %a3 = vector.extract %l0[3] : !qco.qubit from vector<4x!qco.qubit>
  %v1 = vector.from_elements %a2, %a3 : vector<2x!qco.qubit>
  %A = arith.constant dense<[[0.0, 1.0], [1.0, 0.0]]> : vector<2x2xf64>
  %l1 = qvec.global zz(%A) %v1 : vector<2x!qco.qubit>, vector<2x2xf64>
  %b2 = vector.extract %l1[0] : !qco.qubit from vector<2x!qco.qubit>
  %b3 = vector.extract %l1[1] : !qco.qubit from vector<2x!qco.qubit>
  %m = vector.from_elements %a0, %a1, %b2, %b3 : vector<4x!qco.qubit>
  %o, %r = qvec.mz %m : vector<4x!qco.qubit> -> vector<4xi1>
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

// CHECK:      %[[INIT:.*]]:2 = magic.init : !chain, !chain1
// CHECK-NEXT: %[[A:.*]] = magic.zxz %[[INIT]]#0 ions [0, 1] {x = [1.5707963267948966, 1.5707963267948966], z1 = [1.5707963267948966, 1.5707963267948966], z2 = [1.5707963267948966, 1.5707963267948966]} : !chain
// CHECK-NEXT: %[[B0:.*]] = magic.zxz %[[INIT]]#1 ions [2, 3] {{.*}} : !chain1
// CHECK-NEXT: %[[B1:.*]] = magic.active_zz %[[B0]] {angles = dense<{{\[\[}}0.000000e+00, 1.000000e+00], [1.000000e+00, 0.000000e+00]]> : tensor<2x2xf64>} : !chain1
// CHECK-NEXT: %[[MA:.*]]:2 = magic.mzd %[[A]] : !chain -> i1, i1
// CHECK-NEXT: %[[MB:.*]]:2 = magic.mzd %[[B1]] : !chain1 -> i1, i1
// CHECK-NEXT: aux.record_int %[[MA]]#0 : i1
// CHECK-NEXT: aux.record_int %[[MA]]#1 : i1
// CHECK-NEXT: aux.record_int %[[MB]]#0 : i1
// CHECK-NEXT: aux.record_int %[[MB]]#1 : i1
// CHECK-NOT:  arith.constant
// CHECK:      return

// -----

// A program creates only as many ions as it has qubits. Three fit into trap 0, so trap 1 stays empty and is not
// measured.
// CHECK:       !chain = !magic.ion_chain<0, [0:1, 1:1, 2:1]>
// CHECK:       !chain1 = !magic.ion_chain<1, []>
// CHECK-LABEL: func.func @three_qubits
func.func @three_qubits() {
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

// CHECK:      %[[INIT:.*]]:2 = magic.init : !chain, !chain1
// CHECK-NEXT: magic.mzd %[[INIT]]#0 : !chain -> i1, i1, i1
// CHECK-NOT:  magic.mzd
