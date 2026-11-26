// RUN: qcc-opt %s --qcc-one-shot-bufferize="bufferize-function-boundaries" | FileCheck %s

// Classical tensors become memrefs, arrays of qubits stay tensors.
// CHECK-LABEL: func.func @mixed(
// CHECK-SAME:      %[[T:.*]]: memref<2xf64, strided<[?], offset: ?>>, %[[I:.*]]: index) -> f64
func.func @mixed(%t: tensor<2xf64>, %i: index) -> f64 {
  %x = tensor.extract %t[%i] : tensor<2xf64>
  %r = qcc.alloc : tensor<2x!qcc.qubit_ref>
  %q = tensor.extract %r[%i] : tensor<2x!qcc.qubit_ref>
  qref.single rz(%x) %q : f64, !qcc.qubit_ref
  qcc.dealloc %r : tensor<2x!qcc.qubit_ref>
  return %x : f64
}

// CHECK-NEXT: %[[X:.*]] = memref.load %[[T]][%[[I]]] : memref<2xf64, strided<[?], offset: ?>>
// CHECK-NEXT: %[[R:.*]] = qcc.alloc : tensor<2x!qcc.qubit_ref>
// CHECK-NEXT: %[[Q:.*]] = tensor.extract %[[R]][%[[I]]] : tensor<2x!qcc.qubit_ref>
// CHECK-NEXT: qref.single rz(%[[X]]) %[[Q]] : f64, !qcc.qubit_ref
// CHECK-NEXT: qcc.dealloc %[[R]] : tensor<2x!qcc.qubit_ref>
// CHECK-NEXT: return %[[X]] : f64
