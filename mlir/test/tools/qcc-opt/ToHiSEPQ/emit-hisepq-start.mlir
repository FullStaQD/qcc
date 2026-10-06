// RUN: qcc-opt %s -emit-hisepq-start --split-input-file | FileCheck %s

llvm.func @kernel() attributes { qcc.entry_point } {
  llvm.return
}

llvm.func @helper() {
  llvm.return
}

// The original functions survive unchanged.
// CHECK-DAG: llvm.func @kernel()
// CHECK-DAG: llvm.func @helper()

// `__stack_top` is provided by the HiSEP-Q linker script.
// CHECK: llvm.mlir.global external constant @__stack_top() {{.*}} !llvm.array<0 x i8>

// The entry point is called as an ordinary call.
// CHECK-LABEL: llvm.func internal @__qcc_call_entry_point()
// CHECK-SAME:    no_inline
// CHECK-NEXT:    llvm.call @kernel() : () -> ()
// CHECK-NEXT:    llvm.return

// `_start` sets the stack pointer, calls the entry point and loops forever.
// CHECK-LABEL: llvm.func @_start()
// CHECK-DAG:     %[[SP:.*]] = llvm.mlir.addressof @__stack_top
// CHECK-DAG:     %[[CALL:.*]] = llvm.mlir.addressof @__qcc_call_entry_point
// CHECK:         llvm.inline_asm has_side_effects{{.*}}"mv sp, $0{{.*}}jalr ra, 0($1){{.*}}", "r,r" %[[SP]], %[[CALL]]
// CHECK:         llvm.unreachable

// -----

// Results are discarded, but the call still provides what the calling convention needs for them.

llvm.func @returns_results() -> !llvm.struct<(i64, i64)> attributes { qcc.entry_point } {
  %0 = llvm.mlir.poison : !llvm.struct<(i64, i64)>
  llvm.return %0 : !llvm.struct<(i64, i64)>
}

// CHECK-LABEL: llvm.func internal @__qcc_call_entry_point()
// CHECK-NEXT:    llvm.call @returns_results() : () -> !llvm.struct<(i64, i64)>
// CHECK-NEXT:    llvm.return
