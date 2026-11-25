// RUN: qcc-opt %s -convert-qref-to-qir | FileCheck %s

// CHECK-LABEL:   func.func @gates() attributes {
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
func.func @gates() attributes { qcc.entry_point } {
    // Physical qubits: the pointer of a static qubit is its index.
    %q5, %q7 = qcc.static_ref [5, 7] : !qcc.qubit_ref
    // CHECK:           %[[QC5:.*]] = llvm.mlir.constant(5 : i64) : i64
    // CHECK:           %[[QP5:.*]] = llvm.inttoptr %[[QC5]] : i64 to !llvm.ptr
    // CHECK:           %[[QC7:.*]] = llvm.mlir.constant(7 : i64) : i64
    // CHECK:           %[[QP7:.*]] = llvm.inttoptr %[[QC7]] : i64 to !llvm.ptr

    // Supported gates.
    qref.single x %q5 : !qcc.qubit_ref
    // CHECK:           llvm.call @__quantum__qis__x__body(%[[QP5]]) : (!llvm.ptr) -> ()
    qref.single h %q5 : !qcc.qubit_ref
    // CHECK:           llvm.call @__quantum__qis__h__body(%[[QP5]]) : (!llvm.ptr) -> ()
    qref.single s %q5 : !qcc.qubit_ref
    // CHECK:           llvm.call @__quantum__qis__s__body(%[[QP5]]) : (!llvm.ptr) -> ()
    qref.single sdg %q5 : !qcc.qubit_ref
    // CHECK:           llvm.call @__quantum__qis__s__adj(%[[QP5]]) : (!llvm.ptr) -> ()
    qref.single t %q5 : !qcc.qubit_ref
    // CHECK:           llvm.call @__quantum__qis__t__body(%[[QP5]]) : (!llvm.ptr) -> ()
    qref.single tdg %q5 : !qcc.qubit_ref
    // CHECK:           llvm.call @__quantum__qis__t__adj(%[[QP5]]) : (!llvm.ptr) -> ()
    qref.pair cx %q5, %q7 : !qcc.qubit_ref
    // CHECK:           llvm.call @__quantum__qis__cx__body(%[[QP5]], %[[QP7]]) : (!llvm.ptr, !llvm.ptr) -> ()
    %rz_angle = arith.constant 1.5707963267948966 : f64
    qref.single rz(%rz_angle) %q5 : f64, !qcc.qubit_ref
    // CHECK:           %[[ANGLE:.*]] = arith.constant {{.*}} : f64
    // CHECK:           llvm.call @__quantum__qis__rz__body(%[[ANGLE]], %[[QP5]]) : (f64, !llvm.ptr) -> ()
    return
}

// CHECK-LABEL:   func.func @measure_and_reset()
func.func @measure_and_reset() attributes { qcc.entry_point } {
    %q5 = qcc.static_ref [5] : !qcc.qubit_ref
    // CHECK:           %[[QC5:.*]] = llvm.mlir.constant(5 : i64) : i64
    // CHECK:           %[[QP5:.*]] = llvm.inttoptr %[[QC5]] : i64 to !llvm.ptr

    // The result pointer equals the qubit pointer.
    %m5 = qref.measure z %q5 : !qcc.qubit_ref -> i1
    // CHECK:           llvm.call @__quantum__qis__mz__body(%[[QP5]], %[[QP5]]) : (!llvm.ptr, !llvm.ptr) -> ()
    // CHECK:           llvm.call @__quantum__rt__read_result(%[[QP5]]) : (!llvm.ptr) -> i1
    qref.reset z %q5 : !qcc.qubit_ref
    // CHECK:           llvm.call @__quantum__qis__reset__body(%[[QP5]]) : (!llvm.ptr) -> ()
    return
}

// CHECK-LABEL:   func.func @record_int()
func.func @record_int() attributes { qcc.entry_point } {
    %bit = arith.constant true
    // CHECK:           %[[BIT:.*]] = arith.constant true
    %int = arith.constant 42 : i64
    // CHECK:           %[[INT:.*]] = arith.constant 42 : i64

    // Several records are wrapped in a tuple, announced at the first record.
    aux.record_int %bit : i1
    // CHECK:           %[[COUNT:.*]] = llvm.mlir.constant(2 : i64) : i64
    // CHECK:           %[[LABEL_PTR_0:.*]] = llvm.mlir.addressof @".qir_dummy_label" : !llvm.ptr
    // CHECK:           llvm.call @__quantum__rt__tuple_record_output(%[[COUNT]], %[[LABEL_PTR_0]]) : (i64, !llvm.ptr) -> ()
    // CHECK:           %[[LABEL_PTR_1:.*]] = llvm.mlir.addressof @".qir_dummy_label" : !llvm.ptr
    // CHECK:           llvm.call @__quantum__rt__bool_record_output(%[[BIT]], %[[LABEL_PTR_1]]) : (i1, !llvm.ptr) -> ()
    aux.record_int %int : i64
    // CHECK:           %[[LABEL_PTR_2:.*]] = llvm.mlir.addressof @".qir_dummy_label" : !llvm.ptr
    // CHECK:           llvm.call @__quantum__rt__int_record_output(%[[INT]], %[[LABEL_PTR_2]]) : (i64, !llvm.ptr) -> ()
    return
}

// CHECK-LABEL:  func.func @record_memref()
func.func @record_memref() -> i64 attributes { qcc.entry_point } {
    %t = memref.alloc() : memref<3xi64>
    aux.record_memref %t : memref<3xi64>
    %exit_code = arith.constant 0 : i64
    return %exit_code : i64
}

// CHECK:     %[[zero:.*]] = llvm.mlir.zero : !llvm.ptr
// CHECK:     llvm.call @__quantum__rt__initialize(%[[zero]])
// CHECK:     %[[label:.*]] = llvm.mlir.addressof @".qir_dummy_label"
// CHECK:     %[[count:.*]] = llvm.mlir.constant(3 : i64)
// CHECK:     llvm.call @__quantum__rt__array_record_output(%[[count]], %[[label]])
// CHECK:     %[[extract:.*]] = llvm.extractvalue %[[LLVM_STRUCT:.*]][1]
// CHECK:     %[[zero_idx:.*]] = llvm.mlir.constant(0 : i64)
// CHECK:     %[[getelem:.*]] = llvm.getelementptr %[[extract]][%[[zero_idx]]]
// CHECK:     %[[load:.*]] = llvm.load %[[getelem]]
// CHECK:     llvm.call @__quantum__rt__int_record_output(%[[load]], %[[label]])
// CHECK:     %[[one:.*]] = llvm.mlir.constant(1 : i64)
// CHECK:     %[[getelem2:.*]] = llvm.getelementptr %[[extract]][%[[one]]]
// CHECK:     %[[load2:.*]] = llvm.load %[[getelem2]]
// CHECK:     llvm.call @__quantum__rt__int_record_output(%[[load2]], %[[label]])
// CHECK:     %[[two:.*]] = llvm.mlir.constant(2 : i64)
// CHECK:     %[[getelem3:.*]] = llvm.getelementptr %[[extract]][%[[two]]]
// CHECK:     %[[load3:.*]] = llvm.load %[[getelem3]]
// CHECK:     llvm.call @__quantum__rt__int_record_output(%[[load3]], %[[label]])
// CHECK:     %[[const:.*]] = arith.constant 0 : i64
// CHECK:     return %[[const]] : i64
// CHECK:  }

// CHECK-LABEL:   func.func @structured_output_recording
func.func @structured_output_recording() -> i64 attributes { qcc.entry_point } {
    %ref = memref.alloc() : memref<3xi64>

    // Supported measurement operations.
    %q = qcc.static_ref [5] : !qcc.qubit_ref
    %m = qref.measure z %q : !qcc.qubit_ref -> i1
    // CHECK:           %[[MR5:.*]] = llvm.call @__quantum__rt__read_result(%[[RP5:.*]]) : (!llvm.ptr) -> i1
    aux.record_int %m : i1
    // CHECK:           %[[LLVM_CONST:.*]] = llvm.mlir.constant(2 : i64) : i64
    // CHECK:           %[[LABEL_PTR_0:.*]] = llvm.mlir.addressof @".qir_dummy_label" : !llvm.ptr
    // CHECK:           llvm.call @__quantum__rt__tuple_record_output(%[[LLVM_CONST]], %[[LABEL_PTR_0]]) : (i64, !llvm.ptr) -> ()
    // CHECK:           %[[LABEL_PTR_1:.*]] = llvm.mlir.addressof @".qir_dummy_label" : !llvm.ptr
    // CHECK:           llvm.call @__quantum__rt__bool_record_output(%[[MR5]], %[[LABEL_PTR_1]]) : (i1, !llvm.ptr) -> ()
    aux.record_memref %ref : memref<3xi64>
    // CHECK:           %[[LABEL_PTR_2:.*]] = llvm.mlir.addressof @".qir_dummy_label" : !llvm.ptr
    // CHECK:           %[[LLVM_CONST_1:.*]] = llvm.mlir.constant(3 : i64) : i64
    // CHECK:           llvm.call @__quantum__rt__array_record_output(%[[LLVM_CONST_1]], %[[LABEL_PTR_2]]) : (i64, !llvm.ptr) -> ()
    // CHECK:           %[[value:.*]] = llvm.extractvalue %[[LLVM_STRUCT:.*]][1] : !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
    // CHECK:           %[[CONST_1:.*]] = llvm.mlir.constant(0 : i64) : i64
    // CHECK:           %[[ELEM_PTR:.*]] = llvm.getelementptr %[[value]][%[[CONST_1]]] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    // CHECK:           %[[LOAD:.*]] = llvm.load %[[ELEM_PTR]] : !llvm.ptr -> i64
    // CHECK:           llvm.call @__quantum__rt__int_record_output(%[[LOAD]], %[[LABEL_PTR_2]]) : (i64, !llvm.ptr) -> ()
    // CHECK:           %[[CONST2:.*]] = llvm.mlir.constant(1 : i64) : i64
    // CHECK:           %[[ELEM_PTR2:.*]] = llvm.getelementptr %[[value]][%[[CONST2]]] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    // CHECK:           %[[LOAD2:.*]] = llvm.load %[[ELEM_PTR2]] : !llvm.ptr -> i64
    // CHECK:           llvm.call @__quantum__rt__int_record_output(%[[LOAD2]], %[[LABEL_PTR_2]]) : (i64, !llvm.ptr) -> ()
    // CHECK:           %[[CONST3:.*]] = llvm.mlir.constant(2 : i64) : i64
    // CHECK:           %[[ELEM_PTR3:.*]] = llvm.getelementptr %[[value]][%[[CONST3]]] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    // CHECK:           %[[LOAD3:.*]] = llvm.load %[[ELEM_PTR3]] : !llvm.ptr -> i64
    // CHECK:           llvm.call @__quantum__rt__int_record_output(%[[LOAD3]], %[[LABEL_PTR_2]]) : (i64, !llvm.ptr) -> ()
    %exit_code = arith.constant 0 : i64
    return %exit_code : i64
}

// The pass assumes that these decls already exist.
llvm.func @__quantum__rt__initialize(!llvm.ptr)
llvm.func @__quantum__rt__bool_record_output(i1, !llvm.ptr)
llvm.func @__quantum__rt__int_record_output(i64, !llvm.ptr)
llvm.func @__quantum__rt__tuple_record_output(i64, !llvm.ptr)
llvm.func @__quantum__rt__array_record_output(i64, !llvm.ptr)
llvm.func @__quantum__rt__read_result(!llvm.ptr {llvm.readonly}) -> i1
llvm.func @__quantum__qis__mz__body(!llvm.ptr, !llvm.ptr {llvm.writeonly}) attributes {passthrough = ["irreversible"]}
llvm.func @__quantum__qis__reset__body(!llvm.ptr) attributes {passthrough = ["irreversible"]}
llvm.func @__quantum__qis__h__body(!llvm.ptr)
llvm.func @__quantum__qis__x__body(!llvm.ptr)
llvm.func @__quantum__qis__s__body(!llvm.ptr)
llvm.func @__quantum__qis__s__adj(!llvm.ptr)
llvm.func @__quantum__qis__t__body(!llvm.ptr)
llvm.func @__quantum__qis__t__adj(!llvm.ptr)
llvm.func @__quantum__qis__cx__body(!llvm.ptr, !llvm.ptr)
llvm.func @__quantum__qis__rz__body(f64, !llvm.ptr)

// The label needed to lower `aux.record_int` to its corresponding runtime function:
llvm.mlir.global internal constant @".qir_dummy_label"("dummy_label\00") {addr_space = 0 : i32}
