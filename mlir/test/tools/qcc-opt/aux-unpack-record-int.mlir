// RUN: qcc-opt %s --aux-unpack-record-int --split-input-file | FileCheck %s

// A Qrisp Bell pair: two bits packed into one i64, bit k is qubit k.
// CHECK-LABEL: func.func @bell
func.func @bell() attributes {qcc.entry_point} {
  %c1_i64 = arith.constant 1 : i64
  %q0 = qc.static 0 : !qc.qubit
  %q1 = qc.static 1 : !qc.qubit
  %m0 = qc.measure %q0 : !qc.qubit -> i1
  %e0 = arith.extui %m0 : i1 to i64
  %m1 = qc.measure %q1 : !qc.qubit -> i1
  %e1 = arith.extui %m1 : i1 to i64
  %s1 = arith.shli %e1, %c1_i64 : i64
  %packed = arith.ori %e0, %s1 : i64
  aux.record_int %packed : i64
  return
}

// CHECK:      %[[M0:.*]] = qc.measure
// CHECK:      %[[M1:.*]] = qc.measure
// CHECK-NOT:  arith.
// CHECK:      aux.record_int %[[M0]] : i1
// CHECK-NEXT: aux.record_int %[[M1]] : i1
// CHECK-NEXT: return

// -----

// Three bits, the or-tree nested the other way round; the records come out in bit order.
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

// Parts of the tree that are used elsewhere stay.
// CHECK-LABEL: func.func @shared_subtree
func.func @shared_subtree(%m0: i1, %m1: i1) -> i64 {
  %c1_i64 = arith.constant 1 : i64
  %e0 = arith.extui %m0 : i1 to i64
  %e1 = arith.extui %m1 : i1 to i64
  %s1 = arith.shli %e1, %c1_i64 : i64
  %packed = arith.ori %e0, %s1 : i64
  aux.record_int %packed : i64
  return %s1 : i64
}

// CHECK-SAME: (%[[M0:.*]]: i1, %[[M1:.*]]: i1)
// CHECK:      %[[S1:.*]] = arith.shli
// CHECK-NOT:  arith.ori
// CHECK:      aux.record_int %[[M0]] : i1
// CHECK-NEXT: aux.record_int %[[M1]] : i1
// CHECK-NEXT: return %[[S1]]

// -----

// Left alone: a plain bit, a constant, a gap in the bit positions.
// CHECK-LABEL: func.func @not_packed
func.func @not_packed(%m0: i1, %m1: i1) {
  %c2_i64 = arith.constant 2 : i64
  %c7_i64 = arith.constant 7 : i64
  aux.record_int %m0 : i1
  aux.record_int %c7_i64 : i64
  %e1 = arith.extui %m1 : i1 to i64
  %s1 = arith.shli %e1, %c2_i64 : i64
  aux.record_int %s1 : i64
  return
}

// CHECK-SAME: (%[[M0:.*]]: i1, %[[M1:.*]]: i1)
// CHECK:      aux.record_int %[[M0]] : i1
// CHECK:      aux.record_int %{{.*}} : i64
// CHECK:      %[[S1:.*]] = arith.shli
// CHECK:      aux.record_int %[[S1]] : i64
