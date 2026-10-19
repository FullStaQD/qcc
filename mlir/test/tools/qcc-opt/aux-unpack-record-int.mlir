// RUN: qcc-opt %s --aux-unpack-record-int --split-input-file | FileCheck %s

// Three bits packed into one i64, bit k at position k. The records come out in bit order, whatever the shape of the
// or-tree.
// CHECK-LABEL: func.func @three_bits
func.func @three_bits(%m0: i1, %m1: i1, %m2: i1) {
  %c1_i64 = arith.constant 1 : i64
  %c2_i64 = arith.constant 2 : i64
  %e0 = arith.extui %m0 : i1 to i64
  %e1 = arith.extui %m1 : i1 to i64
  %e2 = arith.extui %m2 : i1 to i64
  %s1 = arith.shli %e1, %c1_i64 : i64
  %s2 = arith.shli %e2, %c2_i64 : i64
  %hi = arith.ori %s2, %s1 : i64
  %packed = arith.ori %hi, %e0 : i64
  aux.record_int %packed : i64
  return
}

// CHECK-SAME: (%[[M0:.*]]: i1, %[[M1:.*]]: i1, %[[M2:.*]]: i1)
// CHECK-NOT:  arith.
// CHECK:      aux.record_int %[[M0]] : i1
// CHECK-NEXT: aux.record_int %[[M1]] : i1
// CHECK-NEXT: aux.record_int %[[M2]] : i1

// -----

// Left alone: a plain bit, a gap in the bit positions.
// CHECK-LABEL: func.func @not_packed
func.func @not_packed(%m0: i1, %m1: i1) {
  %c2_i64 = arith.constant 2 : i64
  aux.record_int %m0 : i1
  %e1 = arith.extui %m1 : i1 to i64
  %s1 = arith.shli %e1, %c2_i64 : i64
  aux.record_int %s1 : i64
  return
}

// CHECK-SAME: (%[[M0:.*]]: i1, %[[M1:.*]]: i1)
// CHECK:      aux.record_int %[[M0]] : i1
// CHECK:      %[[S1:.*]] = arith.shli
// CHECK:      aux.record_int %[[S1]] : i64
