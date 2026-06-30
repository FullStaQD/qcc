// RUN: qcc-opt %s -prep-to-qir | FileCheck %s

func.func @test() -> i64 attributes { qcc.entry_point } {
    %exit_code = arith.constant 0 : i64
    return %exit_code : i64
}

// Adds llvm function declarations and module flags (for QIR adaptive capabilities):
// CHECK-LABEL:   func.func @test() -> i64 attributes {qcc.entry_point} {
// CHECK:           %[[CONSTANT_0:.*]] = arith.constant 0 : i64
// CHECK:           return %[[CONSTANT_0]] : i64
// CHECK:         }
// CHECK-DAG:     llvm.func @__quantum__rt__initialize(!llvm.ptr)
// CHECK-DAG:     llvm.func @__quantum__rt__bool_record_output(i1, !llvm.ptr)
// CHECK-DAG:     llvm.func @__quantum__rt__read_result(!llvm.ptr {llvm.readonly}) -> i1
// CHECK-DAG:     llvm.func @__quantum__qis__mz__body(!llvm.ptr, !llvm.ptr {llvm.writeonly}) attributes {passthrough = ["irreversible"]}
// CHECK-DAG:     llvm.func @__quantum__qis__h__body(!llvm.ptr)
// CHECK-DAG:     llvm.func @__quantum__qis__x__body(!llvm.ptr)
// CHECK-DAG:     llvm.func @__quantum__qis__cx__body(!llvm.ptr, !llvm.ptr)
// CHECK-DAG:     llvm.func @__quantum__qis__rz__body(f64, !llvm.ptr)
// CHECK:         llvm.module_flags [
// CHECK-SAME:      #llvm.mlir.module_flag<error, "qir_major_version", 2 : i32>
//                  ... other flags
// CHECK-SAME:    ]
// CHECK:         llvm.mlir.global internal constant @".qir_dummy_label"("dummy_label\00") {addr_space = 0 : i32}
