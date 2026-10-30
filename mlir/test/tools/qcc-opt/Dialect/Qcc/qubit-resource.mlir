// RUN: qcc-opt %s --canonicalize --cse --split-input-file | FileCheck %s

// The memory effects on the `QubitResource`, as canonicalization and CSE see them.

// Operations on qubits are kept although nothing uses their results, also inside regions.
// CHECK-LABEL: func.func @unobserved
func.func @unobserved(%cond: i1) {
  %q0, %q1 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  // CHECK:      qref.single h
  qref.single h %q0 : !qcc.qubit_ref
  // CHECK-NEXT: qref.pair cx
  qref.pair cx %q0, %q1 : !qcc.qubit_ref
  // CHECK-NEXT: qref.measure z
  %bit = qref.measure z %q0 : !qcc.qubit_ref -> i1
  // CHECK-NEXT: qref.reset z
  qref.reset z %q0 : !qcc.qubit_ref
  // CHECK-NEXT: scf.if
  // CHECK-NEXT:   qref.single x
  scf.if %cond {
    qref.single x %q1 : !qcc.qubit_ref
  }
  return
}

// -----

// `qcc.static_ref` is pure: references with the same index become one value, and an unused one is erased.
// CHECK-LABEL: func.func @static_ref_is_pure
func.func @static_ref_is_pure() {
  // CHECK-NEXT: %[[Q:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
  %a = qcc.static_ref [0] : !qcc.qubit_ref
  %b = qcc.static_ref [0] : !qcc.qubit_ref
  %unused = qcc.static_ref [1] : !qcc.qubit_ref
  // CHECK-NEXT: qref.single h %[[Q]] : !qcc.qubit_ref
  qref.single h %a : !qcc.qubit_ref
  // CHECK-NEXT: qref.single x %[[Q]] : !qcc.qubit_ref
  qref.single x %b : !qcc.qubit_ref
  // CHECK-NEXT: return
  return
}

// -----

// Each `qcc.alloc` returns fresh qubits, so two of them are never merged. An unused one is erased; a `qcc.dealloc`
// is kept although it has no results.
// CHECK-LABEL: func.func @alloc
func.func @alloc() {
  // CHECK-NEXT: %[[A:.*]] = qcc.alloc : !qcc.qubit_ref
  %a = qcc.alloc : !qcc.qubit_ref
  // CHECK-NEXT: %[[B:.*]] = qcc.alloc : !qcc.qubit_ref
  %b = qcc.alloc : !qcc.qubit_ref
  %unused = qcc.alloc : tensor<2x!qcc.qubit_ref>
  // CHECK-NEXT: qcc.dealloc %[[A]] : !qcc.qubit_ref
  qcc.dealloc %a : !qcc.qubit_ref
  // CHECK-NEXT: qcc.dealloc %[[B]] : !qcc.qubit_ref
  qcc.dealloc %b : !qcc.qubit_ref
  // CHECK-NEXT: return
  return
}
