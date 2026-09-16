// RUN: qcc-opt %s | FileCheck %s
module {
  func.func @main() -> i64 attributes {passthrough = ["entry_point"]} {
    %0 = qc.alloc : !qc.qubit
    qc.x %0 : !qc.qubit
    qc.dealloc %0 : !qc.qubit
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64 : i64
  }
}

// CHECK-LABEL: @main
// CHECK: [[q0:%.+]] = qc.alloc : !qc.qubit
// CHECK: qc.x [[q0]] : !qc.qubit
// CHECK: qc.dealloc [[q0]] : !qc.qubit
// CHECK: [[c0_i64:%.+]] = arith.constant 0 : i64
// CHECK: return [[c0_i64]] : i64
