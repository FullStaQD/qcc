// RUN: qcc-opt %s --canonicalize | FileCheck %s

// CHECK-LABEL: func.func @remove_unused_qubits
func.func @remove_unused_qubits() {
  %q:4 = qcc.static [0, 2, 3, 5] : !qcc.qubit
  %q2 = qcirc.single h %q#1 : !qcc.qubit // nothing observable happens to this qubit afterwards -> counts as unused.
  %q0, %m0 = qcirc.measure z %q#0 : !qcc.qubit -> i1
  %q5, %m5 = qcirc.measure z %q#3 : !qcc.qubit -> i1
  aux.record_int %m0 : i1
  aux.record_int %m5 : i1
  return
}

// CHECK:      %[[Q:.*]]:2 = qcc.static [0, 5] : !qcc.qubit
// CHECK-NEXT: %{{.*}}, %[[M0:.*]] = qcirc.measure z %[[Q]]#0
// CHECK-NEXT: %{{.*}}, %[[M5:.*]] = qcirc.measure z %[[Q]]#1
// CHECK-NEXT: aux.record_int %[[M0]]
// CHECK-NEXT: aux.record_int %[[M5]]
// CHECK-NEXT: return

// A constant size becomes static, so that `tensor.dim` folds.
// CHECK-LABEL: func.func @static_alloc_size
func.func @static_alloc_size() -> index {
  %c0 = arith.constant 0 : index
  %c3 = arith.constant 3 : index
  %r = qcc.alloc %c3 : tensor<?x!qcc.qubit_ref>
  %q = tensor.extract %r[%c0] : tensor<?x!qcc.qubit_ref>
  qref.single h %q : !qcc.qubit_ref
  %size = tensor.dim %r, %c0 : tensor<?x!qcc.qubit_ref>
  return %size : index
}

// CHECK-DAG:  %[[C0:.*]] = arith.constant 0 : index
// CHECK-DAG:  %[[C3:.*]] = arith.constant 3 : index
// CHECK:      %[[R:.*]] = qcc.alloc : tensor<3x!qcc.qubit_ref>
// CHECK-NEXT: %[[Q:.*]] = tensor.extract %[[R]][%[[C0]]] : tensor<3x!qcc.qubit_ref>
// CHECK-NEXT: qref.single h %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT: return %[[C3]] : index
