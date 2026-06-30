// RUN: qcc-opt %s -while-to-for | FileCheck %s

func.func public @sle_while_to_for(%m: memref<?xf32>, %v: f32) {
  %step = arith.constant 1 : index
  %lb = arith.constant 1 : index
  %zero = arith.constant 0 : index
  %ub_incl = arith.constant 4 : index
  %i_out = scf.while (%i = %lb) : (index) -> (index) {
    %done = arith.cmpi sle, %i, %ub_incl : index
    scf.condition(%done) %i : index
  } do {
  ^bb0(%i: index):
    memref.store %v, %m[%i] : memref<?xf32>
    %next_i = arith.addi %i, %step : index
    scf.yield %next_i : index
  }
  return
}

// CHECK-LABEL:    @sle_while_to_for
// CHECK-DAG:       %[[UB:.*]] = arith.constant 5 : index
// CHECK:           scf.for %[[I:.*]] = %[[LB:.*]] to %[[UB]] step %[[STEP:.*]] {

func.func public @slt_while_to_for() -> i64 {
  %step = arith.constant 1 : i64
  %lb = arith.constant 1 : i64
  %zero = arith.constant 0 : i64
  %ub = arith.constant 5 : i64
  %i_out, %sum = scf.while (%i = %lb, %sum = %zero) : (i64, i64) -> (i64, i64) {
    %done = arith.cmpi slt, %i, %ub : i64
    scf.condition(%done) %i, %sum : i64, i64
  } do {
  ^bb0(%i: i64, %sum: i64):
    %next_i = arith.addi %i, %step : i64
    %next_sum = arith.addi %sum, %i : i64
    scf.yield %next_i, %next_sum : i64, i64
  }
  return %sum : i64
}

// CHECK-LABEL:   func.func public @slt_while_to_for() -> i64 {
// CHECK-DAG:       %[[UB:.*]] = arith.constant 5 : i64
// CHECK-DAG:       %[[STEP:.*]] = arith.constant 1 : i64
// CHECK-DAG:       %[[LB:.*]] = arith.constant 0 : i64
// CHECK:           %[[SUM:.*]] = scf.for %[[I:.*]] = %[[STEP]] to %[[UB]] step %[[STEP]] iter_args(%[[PREVIOUS_SUM:.*]] = %[[LB]]) -> (i64)  : i64 {
// CHECK:             %[[NEXT_SUM:.*]] = arith.addi %[[PREVIOUS_SUM]], %[[I]] : i64
// CHECK:             scf.yield %[[NEXT_SUM]] : i64
// CHECK:           return %[[SUM]] : i64
