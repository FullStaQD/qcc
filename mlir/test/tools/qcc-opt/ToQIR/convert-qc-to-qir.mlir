// RUN: qcc-opt %s -convert-qc-to-qir | FileCheck %s

func.func @test() -> i64 attributes { qcc.entry_point } {
    // CHECK-LABEL:   func.func @test() -> i64 attributes {
    // CHECK-SAME:        passthrough = [
    // CHECK-SAME:          "entry_point",
    // CHECK-SAME:          ["output_labeling_schema", "schema_id"],
    // CHECK-SAME:          ["qir_profiles", "adaptive_profile"],
    // CHECK-SAME:          ["required_num_qubits", "8"],
    // CHECK-SAME:          ["required_num_results", "8"]
    // CHECK-SAME:        ],
    // CHECK-SAME:        qcc.entry_point
    // CHECK-SAME:      } {

    // CHECK:           %[[ZERO_PTR:.*]] = llvm.mlir.zero : !llvm.ptr
    // CHECK:           llvm.call @__quantum__rt__initialize(%[[ZERO_PTR]]) : (!llvm.ptr) -> ()

    // Physical qubits.
    %q5 = qc.static 5 : !qc.qubit
    %q7 = qc.static 7 : !qc.qubit
    // NOTE: static allocations are not directly translated to QIR.

    // Supported unitary operations.
    qc.h %q5 : !qc.qubit
    // CHECK:           %[[QC5:.*]] = llvm.mlir.constant(5 : i64) : i64
    // CHECK:           %[[QP5:.*]] = llvm.inttoptr %[[QC5]] : i64 to !llvm.ptr
    // CHECK:           llvm.call @__quantum__qis__h__body(%[[QP5]]) : (!llvm.ptr) -> ()
    qc.x %q5 : !qc.qubit
    // CHECK:           %[[QC5:.*]] = llvm.mlir.constant(5 : i64) : i64
    // CHECK:           %[[QP5:.*]] = llvm.inttoptr %[[QC5]] : i64 to !llvm.ptr
    // CHECK:           llvm.call @__quantum__qis__x__body(%[[QP5]]) : (!llvm.ptr) -> ()
    qc.ctrl(%q5) { qc.x %q7 : !qc.qubit } : !qc.qubit
    // CHECK-DAG:       %[[QC3:.*]] = llvm.mlir.constant(5 : i64) : i64
    // CHECK-DAG:       %[[QP3:.*]] = llvm.inttoptr %[[QC3]] : i64 to !llvm.ptr
    // CHECK-DAG:       %[[QC7:.*]] = llvm.mlir.constant(7 : i64) : i64
    // CHECK-DAG:       %[[QP7:.*]] = llvm.inttoptr %[[QC7]] : i64 to !llvm.ptr
    // CHECK:           llvm.call @__quantum__qis__cx__body(%[[QP3]], %[[QP7]]) : (!llvm.ptr, !llvm.ptr) -> ()

    // Supported rz rotations.
    %rz_angle = arith.constant 1.5707963267948966 : f64
    qc.rz(%rz_angle) %q5 : !qc.qubit
    // CHECK:           %[[ANGLE:.*]] = arith.constant {{.*}} : f64
    // CHECK-DAG:       %[[QC5_RZ:.*]] = llvm.mlir.constant(5 : i64) : i64
    // CHECK-DAG:       %[[QP5_RZ:.*]] = llvm.inttoptr %[[QC5_RZ]] : i64 to !llvm.ptr
    // CHECK:           llvm.call @__quantum__qis__rz__body(%[[ANGLE]], %[[QP5_RZ]]) : (f64, !llvm.ptr) -> ()

    // Supported measurement operations.
    %m5 = qc.measure %q5 : !qc.qubit -> i1
    // CHECK-DAG:       %[[QC5:.*]] = llvm.mlir.constant(5 : i64) : i64
    // CHECK-DAG:       %[[QP5:.*]] = llvm.inttoptr %[[QC5]] : i64 to !llvm.ptr
    // CHECK-DAG:       %[[RC5:.*]] = llvm.mlir.constant(5 : i64) : i64
    // CHECK-DAG:       %[[RP5:.*]] = llvm.inttoptr %[[RC5]] : i64 to !llvm.ptr
    // CHECK:           llvm.call @__quantum__qis__mz__body(%[[QP5]], %[[RP5]]) : (!llvm.ptr, !llvm.ptr) -> ()
    // CHECK:           %[[MR5:.*]] = llvm.call @__quantum__rt__read_result(%[[RP5]]) : (!llvm.ptr) -> i1
    %m7 = qc.measure %q7 : !qc.qubit -> i1
    // CHECK:           llvm.call @__quantum__qis__mz__body
    // CHECK:           llvm.call @__quantum__rt__read_result

    aux.record_int %m5 : i1
    // CHECK:           %[[LABEL_PTR:.*]] = llvm.mlir.addressof @".qir_dummy_label" : !llvm.ptr
    // CHECK:           llvm.call @__quantum__rt__bool_record_output(%[[MR5]], %[[LABEL_PTR]]) : (i1, !llvm.ptr) -> ()
    aux.record_int %m7 : i1
    // CHECK:           llvm.call @__quantum__rt__bool_record_output
    %record_int = arith.constant 42 : i64
    // CHECK:           %[[CONST_INT:.*]] = arith.constant 42 : i64
    aux.record_int %record_int : i64
    // CHECK:           %[[LABEL_PTR_1:.*]] = llvm.mlir.addressof @".qir_dummy_label" : !llvm.ptr
    // CHECK:           llvm.call @__quantum__rt__int_record_output(%[[CONST_INT]], %[[LABEL_PTR_1]]) : (i64, !llvm.ptr) -> ()

    %exit_code = arith.constant 0 : i64
    return %exit_code : i64
    // CHECK:           %[[EXIT_CODE:.*]] = arith.constant 0 : i64
    // CHECK:           return %[[EXIT_CODE]] : i64
}

// The pass assumes that these decls already exist.
llvm.func @__quantum__rt__initialize(!llvm.ptr)
llvm.func @__quantum__rt__bool_record_output(i1, !llvm.ptr)
llvm.func @__quantum__rt__int_record_output(i64, !llvm.ptr)
llvm.func @__quantum__rt__read_result(!llvm.ptr {llvm.readonly}) -> i1
llvm.func @__quantum__qis__mz__body(!llvm.ptr, !llvm.ptr {llvm.writeonly}) attributes {passthrough = ["irreversible"]}
llvm.func @__quantum__qis__h__body(!llvm.ptr)
llvm.func @__quantum__qis__x__body(!llvm.ptr)
llvm.func @__quantum__qis__cx__body(!llvm.ptr, !llvm.ptr)
llvm.func @__quantum__qis__rz__body(f64, !llvm.ptr)

// The label needed to lower `aux.record_int` to its corresponding runtime function:
llvm.mlir.global internal constant @".qir_dummy_label"("dummy_label\00") {addr_space = 0 : i32}
