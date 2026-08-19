// RUN: qcc --target=hisepq --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-MLIR
// RUN: qcc --target=hisepq --compile-to=native %s -o - | FileCheck %s --check-prefix=CHECK-ASM

// FIXME: remove this file

func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    qc.h %0 : !qc.qubit
    return
}

// The HiSEP-Q lowering runs the full QIR pipeline and then replaces the QIS
// call ops with RISC-V QV intrinsics.
// CHECK-MLIR-LABEL: llvm.func @main()
// CHECK-MLIR-NOT:     llvm.call @__quantum__qis
// CHECK-MLIR:         llvm.call_intrinsic "llvm.riscv.qv.h"({{.*}})
// CHECK-MLIR:         llvm.return

// `main` is tagged as the entry point, so a `_start` is synthesized that sets up the stack from
// the linker-provided `__stack_top` and calls it.
// CHECK-MLIR: llvm.mlir.global external constant @__stack_top
// CHECK-MLIR-LABEL: llvm.func @_start()
// CHECK-MLIR:         llvm.inline_asm{{.*}}"mv sp, $0{{.*}}jalr ra, 0($1){{.*}}"
// CHECK-MLIR:         llvm.unreachable

// CHECK-ASM: main:
// CHECK-ASM: qv.h

// `_start` is the synthesized boot entry point (see hisepq.ld): it sets up the stack and calls
// `main`, so it must also show up in native output.
// CHECK-ASM: _start:
