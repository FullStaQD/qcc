// RUN: qcc-opt %s | FileCheck %s
// RUN: qcc-opt %s --mlir-print-op-generic | qcc-opt | FileCheck %s

// Round trip of the qubit type and its source.

// CHECK-LABEL: func.func @static
func.func @static() {
  // The indices need not be dense or sorted.
  // CHECK: %{{.*}}:3 = qcc.static [3, 0, 7] : !qcc.qubit
  %q3, %q0, %q7 = qcc.static [3, 0, 7] : !qcc.qubit
  return
}

// CHECK-LABEL: func.func @static_single
func.func @static_single() {
  // CHECK: %{{.*}} = qcc.static [0] : !qcc.qubit
  %q0 = qcc.static [0] : !qcc.qubit
  return
}

// CHECK-LABEL: func.func @static_empty
func.func @static_empty() {
  // CHECK: qcc.static [] : !qcc.qubit
  qcc.static [] : !qcc.qubit
  return
}

// A qubit is a vector element.
// CHECK-LABEL: func.func @qubit_vector
func.func @qubit_vector() {
  // CHECK: %[[Q:.*]]:2 = qcc.static [0, 1] : !qcc.qubit
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // CHECK: %[[QS:.*]] = vector.from_elements %[[Q]]#0, %[[Q]]#1 : vector<2x!qcc.qubit>
  %qs = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  // CHECK: vector.extract %[[QS]][1] : !qcc.qubit from vector<2x!qcc.qubit>
  %q = vector.extract %qs[1] : !qcc.qubit from vector<2x!qcc.qubit>
  return
}
