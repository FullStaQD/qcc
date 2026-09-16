// RUN: qcc-opt %s --convert-memref-to-static-qubits | FileCheck %s

// Test that the constant size `memref.alloc` are successfully converted to `qc.static` calls.
func.func public @test(){
    %c2 = arith.constant 2 : index
    %c1 = arith.constant 1 : index
    %c0 = arith.constant 0 : index
    %alloc = memref.alloc() : memref<3x!qc.qubit>
    %0 = memref.load %alloc[%c0] : memref<3x!qc.qubit>
    qc.h %0 : !qc.qubit
    %1 = memref.load %alloc[%c1] : memref<3x!qc.qubit>
    qc.ctrl(%0) targets(%t1 = %1) {
      qc.x %t1 : !qc.qubit
      qc.yield
    } : {!qc.qubit}, {!qc.qubit}
    %2 = memref.load %alloc[%c2] : memref<3x!qc.qubit>
    qc.ctrl(%1) targets(%t2 = %2) {
      qc.x %t2 : !qc.qubit
      qc.yield
    } : {!qc.qubit}, {!qc.qubit}
    %3 = qc.measure %0 : !qc.qubit -> i1
    %4 = qc.measure %1 : !qc.qubit -> i1
    %5 = qc.measure %2 : !qc.qubit -> i1
    return
  }

// CHECK: module {
// CHECK-LABEL:   func.func public @test() {
// CHECK:     %[[Q0:.*]] = qc.static 0 : !qc.qubit
// CHECK:     %[[Q1:.*]] = qc.static 1 : !qc.qubit
// CHECK:     %[[Q2:.*]] = qc.static 2 : !qc.qubit
// CHECK:     qc.h %[[Q0]] : !qc.qubit
// CHECK:     qc.ctrl(%[[Q0]]) targets (%[[T_Q1:.*]] = %[[Q1]]) {
// CHECK:       qc.x %[[T_Q1]] : !qc.qubit
// CHECK:       qc.yield
// CHECK:     } : {{.*!qc.qubit.*!qc.qubit.*}}
// CHECK:     qc.ctrl(%[[Q1]]) targets (%[[T_Q2:.*]] = %[[Q2]]) {
// CHECK:       qc.x %[[T_Q2]] : !qc.qubit
// CHECK:       qc.yield
// CHECK:     } : {{.*!qc.qubit.*!qc.qubit.*}}
// CHECK:     %[[M0:.*]] = qc.measure %[[Q0]] : !qc.qubit -> i1
// CHECK:     %[[M1:.*]] = qc.measure %[[Q1]] : !qc.qubit -> i1
// CHECK:     %[[M2:.*]] = qc.measure %[[Q2]] : !qc.qubit -> i1
// CHECK:     return
// CHECK:   }
// CHECK: }
