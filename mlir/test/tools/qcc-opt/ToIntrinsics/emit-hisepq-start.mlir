// RUN: qcc-opt %s -emit-hisepq-start | FileCheck %s

llvm.func @kernel() attributes { passthrough = ["entry_point"] } {
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

// `_start` sets the stack pointer, jumps to the entry point and loops forever.
// CHECK-LABEL: llvm.func @_start()
// CHECK-DAG:     %[[SP:.*]] = llvm.mlir.addressof @__stack_top
// CHECK-DAG:     %[[ENTRY:.*]] = llvm.mlir.addressof @kernel
// CHECK:         llvm.inline_asm has_side_effects{{.*}}"mv sp, $0{{.*}}jalr ra, 0($1){{.*}}", "r,r" %[[SP]], %[[ENTRY]]
// CHECK:         llvm.unreachable
