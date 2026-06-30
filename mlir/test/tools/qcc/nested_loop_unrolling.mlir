// RUN: qcc --compile-to=mlir %s | FileCheck %s

func.func @main() {
  %qubits = memref.alloc(): memref<2x2x2x!qc.qubit>
  affine.for %i = 0 to 2 {
    affine.for %j = 0 to 2 {
      affine.for %k = 0 to 2 {
          %qubit = memref.load %qubits[%i, %j, %k] : memref<2x2x2x!qc.qubit>
          qc.h %qubit : !qc.qubit
      }
    }
  }
  return
}

// TODO: improve test with check on the particular qubits once
// multi-dimensional memrefs are properly supported (https://github.com/FullStaQD/compiler/issues/99).

// CHECK-LABEL: @main

// exactly 8 gates in total
// CHECK: call @__quantum__qis__h__body
// CHECK: call @__quantum__qis__h__body
// CHECK: call @__quantum__qis__h__body
// CHECK: call @__quantum__qis__h__body
// CHECK: call @__quantum__qis__h__body
// CHECK: call @__quantum__qis__h__body
// CHECK: call @__quantum__qis__h__body
// CHECK: call @__quantum__qis__h__body

// CHECK-NOT: call @__quantum__qis__h__body
