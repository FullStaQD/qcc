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

// CHECK-LABEL: func.func @static_empty
func.func @static_empty() {
  // CHECK: qcc.static [] : !qcc.qubit
  qcc.static [] : !qcc.qubit
  return
}

// A qubit is a valid vector element.
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

// Reference types: classical storage, qubit references, and unsized angles.
// CHECK-LABEL: func.func @references
// CHECK-SAME:    (%[[R:.*]]: !qcc.ref<i1>, %{{.*}}: !qcc.qubit_ref, %{{.*}}: !qcc.angle, %{{.*}}: !qcc.ref<!qcc.angle>)
func.func @references(%r: !qcc.ref<i1>, %q: !qcc.qubit_ref, %a: !qcc.angle, %ra: !qcc.ref<!qcc.angle>) {
  // CHECK: %[[V:.*]] = qcc.ref.load %[[R]] : !qcc.ref<i1>
  %v = qcc.ref.load %r : !qcc.ref<i1>
  // CHECK: qcc.ref.store %[[V]], %[[R]] : !qcc.ref<i1>
  qcc.ref.store %v, %r : !qcc.ref<i1>
  return
}

// A reference holds any classical type, also builtin ones and tensors of them.
// CHECK-LABEL: func.func @classical_references
// CHECK-SAME:    !qcc.ref<index>, %{{.*}}: !qcc.ref<complex<f32>>, %{{.*}}: !qcc.ref<tensor<2xsi8>>, %{{.*}}: !qcc.ref<vector<2xf64>>)
func.func @classical_references(%i: !qcc.ref<index>, %c: !qcc.ref<complex<f32>>, %t: !qcc.ref<tensor<2xsi8>>,
                                %v: !qcc.ref<vector<2xf64>>) {
  return
}
