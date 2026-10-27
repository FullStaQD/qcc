// RUN: qcc-opt %s | FileCheck %s
// RUN: qcc-opt %s --mlir-print-op-generic | qcc-opt | FileCheck %s

// Round trip of the qubit type and its source.

// CHECK-LABEL: func.func @static
func.func @static() {
  // The indices need not be dense.
  // CHECK: %{{.*}}:3 = qcc.static [0, 3, 7] : !qcc.qubit
  %q0, %q3, %q7 = qcc.static [0, 3, 7] : !qcc.qubit
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

// References to static qubits. Unlike `qcc.static`, the op may sit anywhere, also more than once per function.
// CHECK-LABEL: func.func @static_ref
func.func @static_ref(%cond: i1) {
  // CHECK: %{{.*}}:3 = qcc.static_ref [0, 3, 7] : !qcc.qubit_ref
  %q0, %q3, %q7 = qcc.static_ref [0, 3, 7] : !qcc.qubit_ref
  // CHECK: qcc.static_ref [] : !qcc.qubit_ref
  qcc.static_ref [] : !qcc.qubit_ref
  scf.if %cond {
    // CHECK: qcc.static_ref [0] : !qcc.qubit_ref
    %q = qcc.static_ref [0] : !qcc.qubit_ref
  }
  return
}

// CHECK-LABEL: func.func @alloc_and_dealloc
// CHECK-SAME:    (%[[N:.*]]: index)
func.func @alloc_and_dealloc(%n: index) {
  // CHECK: %[[Q:.*]] = qcc.alloc : !qcc.qubit_ref
  %q = qcc.alloc : !qcc.qubit_ref
  // CHECK: %[[R:.*]] = qcc.alloc %[[N]] : tensor<?x!qcc.qubit_ref>
  %r = qcc.alloc %n : tensor<?x!qcc.qubit_ref>
  // CHECK: qcc.alloc : tensor<3x!qcc.qubit_ref>
  %s = qcc.alloc : tensor<3x!qcc.qubit_ref>
  // A qubit array may be empty.
  // CHECK: qcc.alloc : tensor<0x!qcc.qubit_ref>
  %e = qcc.alloc : tensor<0x!qcc.qubit_ref>
  // CHECK: qcc.dealloc %[[Q]] : !qcc.qubit_ref
  qcc.dealloc %q : !qcc.qubit_ref
  // CHECK: qcc.dealloc %[[R]] : tensor<?x!qcc.qubit_ref>
  qcc.dealloc %r : tensor<?x!qcc.qubit_ref>
  return
}

// The parts of arrays can be freed: an element, a slice, a concatenation.
// CHECK-LABEL: func.func @dealloc_parts
func.func @dealloc_parts() {
  %r = qcc.alloc : tensor<4x!qcc.qubit_ref>
  %s = qcc.alloc : tensor<2x!qcc.qubit_ref>
  %c0 = arith.constant 0 : index
  // CHECK: %[[ELEMENT:.*]] = tensor.extract
  %element = tensor.extract %r[%c0] : tensor<4x!qcc.qubit_ref>
  // CHECK: qcc.dealloc %[[ELEMENT]] : !qcc.qubit_ref
  qcc.dealloc %element : !qcc.qubit_ref
  // CHECK: %[[SLICE:.*]] = tensor.extract_slice
  %slice = tensor.extract_slice %r[1] [2] [1] : tensor<4x!qcc.qubit_ref> to tensor<2x!qcc.qubit_ref>
  // CHECK: qcc.dealloc %[[SLICE]] : tensor<2x!qcc.qubit_ref>
  qcc.dealloc %slice : tensor<2x!qcc.qubit_ref>
  %last = tensor.extract_slice %r[3] [1] [1] : tensor<4x!qcc.qubit_ref> to tensor<1x!qcc.qubit_ref>
  // CHECK: %[[BOTH:.*]] = tensor.concat
  %both = tensor.concat dim(0) %last, %s
      : (tensor<1x!qcc.qubit_ref>, tensor<2x!qcc.qubit_ref>) -> tensor<3x!qcc.qubit_ref>
  // CHECK: qcc.dealloc %[[BOTH]] : tensor<3x!qcc.qubit_ref>
  qcc.dealloc %both : tensor<3x!qcc.qubit_ref>
  return
}
