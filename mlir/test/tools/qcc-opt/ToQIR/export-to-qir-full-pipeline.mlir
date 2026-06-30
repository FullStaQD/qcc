// RUN: qcc-opt %s -pass-pipeline="builtin.module(prep-to-qir,func.func(convert-arith-to-llvm,convert-qc-to-qir),convert-cf-to-llvm,finalize-to-qir)" | mlir-translate -mlir-to-llvmir | FileCheck %s

func.func @simple_quantum_with_branching() -> i64 attributes { qcc.entry_point } {
    %0 = qc.static 1 : !qc.qubit

    qc.h %0 : !qc.qubit
    qc.x %0 : !qc.qubit

    %m0 = qc.measure %0 : !qc.qubit -> i1

    cf.cond_br %m0, ^bb_true, ^bb_exit
    ^bb_true:
      qc.x %0 : !qc.qubit
      cf.br ^bb_exit
    ^bb_exit:

    %m1 = qc.measure %0 : !qc.qubit -> i1
    aux.record_int %m1 : i1

    %exit_code = func.call @zero() : () -> i64
    return %exit_code : i64
}

/// just for fun
func.func @zero() -> i64 {
  %1 = arith.constant 0 : i64
  return %1 : i64
}

// CHECK:            source_filename = "LLVMDialectModule"
// CHECK:            @.qir_dummy_label = internal constant [12 x i8] c"dummy_label\00"

// CHECK-LABEL:      define i64 @simple_quantum_with_branching()
// CHECK-SAME:       #[[ATTR0:[0-9]+]] {
// CHECK-NEXT:         call void @__quantum__rt__initialize(ptr null)
// CHECK-NEXT:         call void @__quantum__qis__h__body(ptr inttoptr (i64 1 to ptr))
// CHECK-NEXT:         call void @__quantum__qis__x__body(ptr inttoptr (i64 1 to ptr))
// CHECK-NEXT:         call void @__quantum__qis__mz__body(ptr inttoptr (i64 1 to ptr), ptr inttoptr (i64 1 to ptr))
// CHECK-NEXT:         %[[RES1:.*]] = call i1 @__quantum__rt__read_result(ptr inttoptr (i64 1 to ptr))
// CHECK-NEXT:         br i1 %[[RES1]], label %[[LBL2:.*]], label %[[LBL3:.*]]

// CHECK:           [[LBL2]]:
// CHECK-NEXT:        call void @__quantum__qis__x__body(ptr inttoptr (i64 1 to ptr))
// CHECK-NEXT:        br label %[[LBL3]]

// CHECK:           [[LBL3]]:
// CHECK-NEXT:        call void @__quantum__qis__mz__body(ptr inttoptr (i64 1 to ptr), ptr inttoptr (i64 1 to ptr))
// CHECK-NEXT:        %[[RES2:.*]] = call i1 @__quantum__rt__read_result(ptr inttoptr (i64 1 to ptr))
// CHECK-NEXT:        call void @__quantum__rt__bool_record_output(i1 %[[RES2]], ptr @.qir_dummy_label)
// CHECK-NEXT:        %[[EXIT_CODE:.*]] = call i64 @zero()
// CHECK-NEXT:        ret i64 %[[EXIT_CODE]]
// CHECK:           }

// CHECK:           define i64 @zero() {
// CHECK:             ret i64 0
// CHECK:           }

// CHECK-DAG:       declare void @__quantum__rt__initialize(ptr)
// CHECK-DAG:       declare void @__quantum__rt__bool_record_output(i1, ptr)
// CHECK-DAG:       declare i1 @__quantum__rt__read_result(ptr readonly)
// CHECK-DAG:       declare void @__quantum__qis__mz__body(ptr, ptr writeonly) #[[ATTR1:[0-9]+]]
// CHECK-DAG:       declare void @__quantum__qis__h__body(ptr)
// CHECK-DAG:       declare void @__quantum__qis__x__body(ptr)
// CHECK-DAG:       declare void @__quantum__qis__cx__body(ptr, ptr)

// CHECK:           attributes #[[ATTR0]] = { {{.*}} }
// CHECK:           attributes #[[ATTR1]] = { "irreversible" }

// CHECK:           !llvm.module.flags = !{![[M0:[0-9]+]], {{.*}}}
// CHECK-DAG:       ![[M0]] = !{i32 1, !"qir_major_version", i32 2}
// CHECK-DAG:       ![[#]] = !{i32 7, !"qir_minor_version", i32 1}
// CHECK-DAG:       ![[#]] = !{i32 1, !"dynamic_qubit_management", i32 0}
// CHECK-DAG:       ![[#]] = !{i32 1, !"dynamic_result_management", i32 0}
// CHECK-DAG:       ![[#]] = !{i32 1, !"ir_functions", i32 1}
// CHECK-DAG:       ![[#]] = !{i32 1, !"backwards_branching", i32 1}
// CHECK-DAG:       ![[#]] = !{i32 1, !"multiple_target_branching", i32 0}
// CHECK-DAG:       ![[#]] = !{i32 1, !"multiple_return_points", i32 0}
