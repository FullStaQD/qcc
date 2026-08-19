// RUN: qcc-opt %s -convert-qir-to-intrinsics | FileCheck %s

// Input: a module as produced by the ToQIR pipeline.
// Each qubit is an `!llvm.ptr` obtained via `llvm.inttoptr` of a constant index.
// QIS gate calls use those ptrs as operands.
//
// Expected output: every QIS call is replaced by an `llvm.call_intrinsic` call
// with the qubit encoded as a `vector<[8]xi8>` scalable vector in lane 0.

llvm.func @__quantum__rt__initialize(!llvm.ptr) -> ()
llvm.func @__quantum__rt__read_result(!llvm.ptr) -> i1 attributes {arg_attrs = [{llvm.readonly}]}
llvm.func @__quantum__rt__bool_record_output(i1, !llvm.ptr) -> ()
llvm.func @__quantum__qis__h__body(!llvm.ptr) -> ()
llvm.func @__quantum__qis__x__body(!llvm.ptr) -> ()
llvm.func @__quantum__qis__cx__body(!llvm.ptr, !llvm.ptr) -> ()
llvm.func @__quantum__qis__mz__body(!llvm.ptr, !llvm.ptr) -> ()

llvm.mlir.global internal constant @".qir_dummy_label"("dummy_label\00") {addr_space = 0 : i32}

llvm.func @single_qubit_gates() {
  %c0 = llvm.mlir.constant(0 : i64) : i64
  %q0 = llvm.inttoptr %c0 : i64 to !llvm.ptr
  %c1 = llvm.mlir.constant(1 : i64) : i64
  %q1 = llvm.inttoptr %c1 : i64 to !llvm.ptr

  llvm.call @__quantum__qis__h__body(%q0) : (!llvm.ptr) -> ()
  llvm.call @__quantum__qis__x__body(%q1) : (!llvm.ptr) -> ()
  llvm.return
}

// CHECK-LABEL: llvm.func @single_qubit_gates()
// CHECK-NOT:     llvm.call @__quantum__qis__h__body
// CHECK-NOT:     llvm.call @__quantum__qis__x__body
// CHECK-DAG:     %[[IDX0:.*]] = llvm.mlir.constant(0 : i8) : i8
// CHECK-DAG:     %[[IDX1:.*]] = llvm.mlir.constant(1 : i8) : i8
// CHECK-DAG:     %[[ZERO:.*]] = llvm.mlir.constant(0 : i32) : i32
// CHECK-DAG:     %[[ONE:.*]] = llvm.mlir.constant(1 : i32) : i32
// CHECK-DAG:     %[[POISON_VEC:.*]] = llvm.mlir.poison : vector<[8]xi8>
// CHECK:         %[[VEC0:.*]] = llvm.insertelement %[[IDX0]], %[[POISON_VEC]][%[[ZERO]] : i32] : vector<[8]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"(%[[VEC0]], %[[ZERO]], %[[ZERO]], %[[ONE]])
// CHECK:         %[[VEC1:.*]] = llvm.insertelement %[[IDX1]], %[[POISON_VEC]][%[[ZERO]] : i32] : vector<[8]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.x"(%[[VEC1]], %[[ZERO]], %[[ZERO]], %[[ONE]])


llvm.func @two_qubit_gates() {
  %c2 = llvm.mlir.constant(2 : i64) : i64
  %ctrl = llvm.inttoptr %c2 : i64 to !llvm.ptr
  %c3 = llvm.mlir.constant(3 : i64) : i64
  %tgt  = llvm.inttoptr %c3 : i64 to !llvm.ptr

  llvm.call @__quantum__qis__cx__body(%ctrl, %tgt) : (!llvm.ptr, !llvm.ptr) -> ()
  llvm.return
}

// CHECK-LABEL: llvm.func @two_qubit_gates()
// CHECK-NOT:     llvm.call @__quantum__qis__cx__body
// CHECK-DAG:     %[[CIDX:.*]] = llvm.mlir.constant(2 : i8) : i8
// CHECK-DAG:     %[[TIDX:.*]] = llvm.mlir.constant(3 : i8) : i8
// CHECK-DAG:     %[[ZERO:.*]] = llvm.mlir.constant(0 : i32) : i32
// CHECK-DAG:     %[[ONE:.*]] = llvm.mlir.constant(1 : i32) : i32
// CHECK-DAG:     %[[POISON_VEC:.*]] = llvm.mlir.poison : vector<[8]xi8>
// CHECK:         %[[CVEC:.*]] = llvm.insertelement %[[CIDX]], %[[POISON_VEC]][%[[ZERO]] : i32] : vector<[8]xi8>
// CHECK:         %[[TVEC:.*]] = llvm.insertelement %[[TIDX]], %[[POISON_VEC]][%[[ZERO]] : i32] : vector<[8]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.cx"(%[[CVEC]], %[[TVEC]], %[[ZERO]], %[[ONE]])

// TODO: HiSEP-Q doesn't yet have a `qv.read_result` intrinsic, so the `__quantum__rt__read_result`
// call is replaced with `poison : i1` for now. Once the intrinsic is available, this test should be
// updated to check for it.
llvm.func @measurement() -> i1 {
  %c0 = llvm.mlir.constant(0 : i64) : i64
  %qptr = llvm.inttoptr %c0 : i64 to !llvm.ptr
  %rptr = llvm.inttoptr %c0 : i64 to !llvm.ptr

  llvm.call @__quantum__qis__mz__body(%qptr, %rptr) : (!llvm.ptr, !llvm.ptr) -> ()
  %res = llvm.call @__quantum__rt__read_result(%rptr) : (!llvm.ptr) -> i1
  llvm.return %res : i1
}

// CHECK-LABEL: llvm.func @measurement()
// CHECK-NOT:     llvm.call @__quantum__qis__mz__body
// CHECK-NOT:     llvm.call @__quantum__rt__read_result
// CHECK-DAG:     %[[IDX:.*]] = llvm.mlir.constant(0 : i8) : i8
// CHECK-DAG:     %[[ZERO:.*]] = llvm.mlir.constant(0 : i32) : i32
// CHECK-DAG:     %[[ONE:.*]] = llvm.mlir.constant(1 : i32) : i32
// CHECK-DAG:     %[[POISON_VEC:.*]] = llvm.mlir.poison : vector<[8]xi8>
// CHECK-DAG:     %[[POISON_I1:.*]] = llvm.mlir.poison : i1
// CHECK:         %[[VEC:.*]] = llvm.insertelement %[[IDX]], %[[POISON_VEC]][%[[ZERO]] : i32] : vector<[8]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.mz"(%[[VEC]], %[[ZERO]], %[[ZERO]], %[[ONE]])
// CHECK:         llvm.return %[[POISON_I1]] : i1


llvm.func @rt_calls_erased() {
  %null = llvm.mlir.zero : !llvm.ptr
  llvm.call @__quantum__rt__initialize(%null) : (!llvm.ptr) -> ()

  %c0 = llvm.mlir.constant(0 : i64) : i64
  %qptr = llvm.inttoptr %c0 : i64 to !llvm.ptr
  llvm.call @__quantum__qis__x__body(%qptr) : (!llvm.ptr) -> ()

  %false = llvm.mlir.constant(0 : i1) : i1
  %label = llvm.mlir.addressof @".qir_dummy_label" : !llvm.ptr
  llvm.call @__quantum__rt__bool_record_output(%false, %label) : (i1, !llvm.ptr) -> ()

  llvm.return
}

// CHECK-LABEL: llvm.func @rt_calls_erased()
// CHECK-NOT:     llvm.call @__quantum__rt__initialize
// CHECK-NOT:     llvm.call @__quantum__rt__bool_record_output
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.x"

// The eagerly-declared QIR runtime/QIS declarations are all removed once unused.
// CHECK-NOT: llvm.func @__quantum__qis__h__body
// CHECK-NOT: llvm.func @__quantum__qis__x__body
// CHECK-NOT: llvm.func @__quantum__qis__cx__body
// CHECK-NOT: llvm.func @__quantum__qis__mz__body
// CHECK-NOT: llvm.func @__quantum__rt__initialize
// CHECK-NOT: llvm.func @__quantum__rt__read_result
// CHECK-NOT: llvm.func @__quantum__rt__bool_record_output
