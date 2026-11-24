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
