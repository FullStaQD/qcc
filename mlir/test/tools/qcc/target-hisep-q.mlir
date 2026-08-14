// RUN: %if hisep-q %{ qcc --list-targets | FileCheck %s --check-prefix=CHECK-LIST %}
// RUN: %if hisep-q %{ qcc --target=hisep-q --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-MLIR %}
// RUN: %if hisep-q %{ qcc --target=hisep-q --compile-to=native %s -o - | FileCheck %s --check-prefix=CHECK-ASM %}

// RUN: %if hisep-q %{ qcc --target=hisep-q --compile-to=native --binary %s -o %t.o %}
// RUN: %if hisep-q %{ llvm-objdump -d %t.o | FileCheck %s --check-prefix=CHECK-OBJ %}

// RUN: %if !hisep-q %{ qcc --list-targets | FileCheck %s --check-prefix=CHECK-NOLIST %}
// RUN: %if !hisep-q %{ not qcc --target=hisep-q %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR %}

// FIXME: is this %if stuff really the way to go? Instead of REQUIRES and UNSUPPORTED?

func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    qc.h %0 : !qc.qubit
    return
}

// FIXME: calling hisepq (not hisep-q)?
// CHECK-LIST: hisep-q - HiSEP-Q QISA target

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
// CHECK-OBJ: <main>:
// CHECK-OBJ: qv.h

// `_start` is the synthesized boot entry point (see hisepq.ld): it sets up the stack and calls
// `main`, so it must also show up in native output.
// CHECK-ASM: _start:
// CHECK-OBJ: <_start>:

// Without the target built in, it must not be advertised and must be diagnosed as unknown.
// CHECK-NOLIST: Available targets for --target:
// CHECK-NOLIST-NOT: hisep-q
// CHECK-ERR: error: unknown target 'hisep-q'
