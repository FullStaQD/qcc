// RUN: qcc-opt %s | FileCheck %s
// RUN: qcc-opt %s --mlir-print-op-generic | qcc-opt | FileCheck %s

// CHECK-LABEL: func.func @single_gates
func.func @single_gates() {
  // CHECK: %[[Q:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  // CHECK: qref.single x %[[Q]] : !qcc.qubit_ref
  qref.single x %q : !qcc.qubit_ref
  // CHECK: qref.single y %[[Q]] : !qcc.qubit_ref
  qref.single y %q : !qcc.qubit_ref
  // CHECK: qref.single z %[[Q]] : !qcc.qubit_ref
  qref.single z %q : !qcc.qubit_ref
  // CHECK: qref.single h %[[Q]] : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  // CHECK: qref.single s %[[Q]] : !qcc.qubit_ref
  qref.single s %q : !qcc.qubit_ref
  // CHECK: qref.single sdg %[[Q]] : !qcc.qubit_ref
  qref.single sdg %q : !qcc.qubit_ref
  // CHECK: qref.single t %[[Q]] : !qcc.qubit_ref
  qref.single t %q : !qcc.qubit_ref
  // CHECK: qref.single tdg %[[Q]] : !qcc.qubit_ref
  qref.single tdg %q : !qcc.qubit_ref
  // CHECK: qref.single sx %[[Q]] : !qcc.qubit_ref
  qref.single sx %q : !qcc.qubit_ref
  // CHECK: qref.single sxdg %[[Q]] : !qcc.qubit_ref
  qref.single sxdg %q : !qcc.qubit_ref
  return
}

// CHECK-LABEL: func.func @parametrised_single_gates
// CHECK-SAME: (%[[A:.*]]: f64, %[[B:.*]]: f64, %[[C:.*]]: f64)
func.func @parametrised_single_gates(%a: f64, %b: f64, %c: f64) {
  // CHECK: %[[Q:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  // CHECK: qref.single rx(%[[A]]) %[[Q]] : f64, !qcc.qubit_ref
  qref.single rx(%a) %q : f64, !qcc.qubit_ref
  // CHECK: qref.single ry(%[[A]]) %[[Q]] : f64, !qcc.qubit_ref
  qref.single ry(%a) %q : f64, !qcc.qubit_ref
  // CHECK: qref.single rz(%[[A]]) %[[Q]] : f64, !qcc.qubit_ref
  qref.single rz(%a) %q : f64, !qcc.qubit_ref
  // Three parameters share one type.
  // CHECK: qref.single u_zxz(%[[A]], %[[B]], %[[C]]) %[[Q]] : f64, !qcc.qubit_ref
  qref.single u_zxz(%a, %b, %c) %q : f64, !qcc.qubit_ref
  // CHECK: qref.single u_zyz(%[[A]], %[[B]], %[[C]]) %[[Q]] : f64, !qcc.qubit_ref
  qref.single u_zyz(%a, %b, %c) %q : f64, !qcc.qubit_ref
  return
}

// CHECK-LABEL: func.func @pair_gates
// CHECK-SAME: (%[[THETA:.*]]: f64)
func.func @pair_gates(%theta: f64) {
  // CHECK: %[[Q:.*]]:2 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  %a, %b = qcc.static_ref [0, 1] : !qcc.qubit_ref
  // CHECK: qref.pair cx %[[Q]]#0, %[[Q]]#1 : !qcc.qubit_ref
  qref.pair cx %a, %b : !qcc.qubit_ref
  // CHECK: qref.pair cy %[[Q]]#0, %[[Q]]#1 : !qcc.qubit_ref
  qref.pair cy %a, %b : !qcc.qubit_ref
  // CHECK: qref.pair cz %[[Q]]#0, %[[Q]]#1 : !qcc.qubit_ref
  qref.pair cz %a, %b : !qcc.qubit_ref
  // CHECK: qref.pair swap %[[Q]]#1, %[[Q]]#0 : !qcc.qubit_ref
  qref.pair swap %b, %a : !qcc.qubit_ref
  // CHECK: qref.pair iswap %[[Q]]#0, %[[Q]]#1 : !qcc.qubit_ref
  qref.pair iswap %a, %b : !qcc.qubit_ref
  // CHECK: qref.pair cp(%[[THETA]]) %[[Q]]#0, %[[Q]]#1 : f64, !qcc.qubit_ref
  qref.pair cp(%theta) %a, %b : f64, !qcc.qubit_ref
  // CHECK: qref.pair crz(%[[THETA]]) %[[Q]]#0, %[[Q]]#1 : f64, !qcc.qubit_ref
  qref.pair crz(%theta) %a, %b : f64, !qcc.qubit_ref
  // CHECK: qref.pair rxx(%[[THETA]]) %[[Q]]#0, %[[Q]]#1 : f64, !qcc.qubit_ref
  qref.pair rxx(%theta) %a, %b : f64, !qcc.qubit_ref
  // CHECK: qref.pair ryy(%[[THETA]]) %[[Q]]#0, %[[Q]]#1 : f64, !qcc.qubit_ref
  qref.pair ryy(%theta) %a, %b : f64, !qcc.qubit_ref
  // CHECK: qref.pair rzz(%[[THETA]]) %[[Q]]#0, %[[Q]]#1 : f64, !qcc.qubit_ref
  qref.pair rzz(%theta) %a, %b : f64, !qcc.qubit_ref
  return
}

// CHECK-LABEL: func.func @measure_and_reset
func.func @measure_and_reset() -> (i1, i1) {
  // CHECK: %[[Q:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  // CHECK: %[[BIT_Z:.*]] = qref.measure z %[[Q]] : !qcc.qubit_ref -> i1
  %bit_z = qref.measure z %q : !qcc.qubit_ref -> i1
  // CHECK: qref.reset z %[[Q]] : !qcc.qubit_ref
  qref.reset z %q : !qcc.qubit_ref
  // CHECK: qref.reset x %[[Q]] : !qcc.qubit_ref
  qref.reset x %q : !qcc.qubit_ref
  // CHECK: %[[BIT_X:.*]] = qref.measure x %[[Q]] : !qcc.qubit_ref -> i1
  %bit_x = qref.measure x %q : !qcc.qubit_ref -> i1
  // CHECK: return %[[BIT_Z]], %[[BIT_X]]
  return %bit_z, %bit_x : i1, i1
}

// References are plain values: standard control flow uses them without bindings or yields.
func.func @control_flow(%n: index) -> i1 {
  %q0, %q1 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  %bit = qref.measure z %q0 : !qcc.qubit_ref -> i1
  scf.if %bit {
    qref.single x %q1 : !qcc.qubit_ref
  }
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  scf.for %i = %c0 to %n step %c1 {
    qref.pair cz %q0, %q1 : !qcc.qubit_ref
  }
  %m = qref.measure z %q1 : !qcc.qubit_ref -> i1
  return %m : i1
}
// CHECK-LABEL: func.func @control_flow
// CHECK:         %[[Q:.*]]:2 = qcc.static_ref [0, 1] : !qcc.qubit_ref
// CHECK-NEXT:    %[[BIT:.*]] = qref.measure z %[[Q]]#0 : !qcc.qubit_ref -> i1
// CHECK-NEXT:    scf.if %[[BIT]] {
// CHECK-NEXT:      qref.single x %[[Q]]#1 : !qcc.qubit_ref
// CHECK-NEXT:    }
// CHECK:         scf.for
// CHECK-NEXT:      qref.pair cz %[[Q]]#0, %[[Q]]#1 : !qcc.qubit_ref
// CHECK-NEXT:    }
// CHECK-NEXT:    qref.measure z %[[Q]]#1 : !qcc.qubit_ref -> i1

// The qubits of an array are tensor elements; a gate acts on one element at a time.
func.func @array(%n: index) {
  %r = qcc.alloc %n : tensor<?x!qcc.qubit_ref>
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  scf.parallel (%i) = (%c0) to (%n) step (%c1) {
    %q = tensor.extract %r[%i] : tensor<?x!qcc.qubit_ref>
    qref.single h %q : !qcc.qubit_ref
  }
  qcc.dealloc %r : tensor<?x!qcc.qubit_ref>
  return
}
// CHECK-LABEL: func.func @array
// CHECK:         %[[R:.*]] = qcc.alloc %{{.*}} : tensor<?x!qcc.qubit_ref>
// CHECK:         scf.parallel
// CHECK-NEXT:      %[[Q:.*]] = tensor.extract %[[R]][%{{.*}}] : tensor<?x!qcc.qubit_ref>
// CHECK-NEXT:      qref.single h %[[Q]] : !qcc.qubit_ref
// CHECK:         qcc.dealloc %[[R]] : tensor<?x!qcc.qubit_ref>
