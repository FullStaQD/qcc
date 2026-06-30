// RUN: qcc-opt %s -convert-return-to-output-recording --split-input-file --verify-diagnostics | FileCheck %s

//===----------------------------------------------------------------------===//
//
// Integer output recording pass tests
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Entry point function returning i64 should be transformed
//===----------------------------------------------------------------------===//

func.func @test_entry_point_i64() -> i64 attributes { qcc.entry_point } {
  %c = arith.constant 1 : i64
  return %c : i64
}
// CHECK-LABEL:   func.func @test_entry_point_i64() attributes {qcc.entry_point} {
// CHECK:     %[[constant:.*]] = arith.constant 1 : i64
// CHECK:     aux.record_int %[[constant]] : i64
// CHECK:     return
// CHECK:   }

//===----------------------------------------------------------------------===//
// No return value should not be transformed, even if the function is an entry point
//===----------------------------------------------------------------------===//

func.func @test_void_entry_point() attributes { qcc.entry_point } {
  %c = arith.constant 1 : i64
  return
}
// CHECK-LABEL:   func.func @test_void_entry_point() attributes {qcc.entry_point} {
// CHECK:     %[[constant:.*]] = arith.constant 1 : i64
// CHECK:     return
// CHECK:   }

//===----------------------------------------------------------------------===//
// Multiple i64 return values should be transformed
//===----------------------------------------------------------------------===//

func.func @test_multiple_i64() -> (i64, i64) attributes { qcc.entry_point } {
  %a = arith.constant 1 : i64
  %b = arith.constant 2 : i64
  return %a, %b : i64, i64
}

// CHECK-LABEL:   func.func @test_multiple_i64() attributes {qcc.entry_point} {
// CHECK:     %[[constant0:.*]] = arith.constant 1 : i64
// CHECK:     %[[constant1:.*]] = arith.constant 2 : i64
// CHECK:     aux.record_int %[[constant0]] : i64
// CHECK:     aux.record_int %[[constant1]] : i64
// CHECK:     return
// CHECK:   }

//===----------------------------------------------------------------------===//
// Function without entry point attribute should not be transformed
//===----------------------------------------------------------------------===//

func.func @test_no_entry_point_attribute() -> (i64, i64) attributes {} {
  %a = arith.constant 42 : i64
  %b = arith.constant 2 : i64
  return %a, %b : i64, i64
}

// CHECK-LABEL:   func.func @test_no_entry_point_attribute() -> (i64, i64) {
// CHECK:     %[[constant0:.*]] = arith.constant 42 : i64
// CHECK:     %[[constant1:.*]] = arith.constant 2 : i64
// CHECK:     return %[[constant0]], %[[constant1]] : i64, i64
// CHECK:   }

//===----------------------------------------------------------------------===//
// Multiple returns mixed between i64 and i1
//===----------------------------------------------------------------------===//

func.func @test_multiple_returns() -> (i64, i1) attributes { qcc.entry_point } {
  %a = arith.constant 2 : i64
  %b = arith.constant 1 : i1
  return %a, %b : i64, i1
}

// CHECK-LABEL:   func.func @test_multiple_returns() attributes {qcc.entry_point} {
// CHECK:     %[[constant0:.*]] = arith.constant 2 : i64
// CHECK:     %[[constant1:.*]] = arith.constant true
// CHECK:     aux.record_int %[[constant0]] : i64
// CHECK:     aux.record_int %[[constant1]] : i1
// CHECK:     return
// CHECK:   }

// -----

// expected-error @+1 {{Non-integer return types are not supported.}}
func.func @test_unsupported_returns() -> (!qc.qubit, i1) attributes { qcc.entry_point } {
  %0 = qc.alloc("q", 1, 0) : !qc.qubit
  %1 = arith.constant 1 : i1

  return %0, %1 : !qc.qubit, i1
}
