// REQUIRES: hisep-q
// RUN: qcc --target=hisep-q --compile-to=native %s -o - | FileCheck %s --check-prefix=CHECK-ASM
// RUN: qcc --target=hisep-q --compile-to=native --binary %s -o %t.o
// RUN: llvm-objdump -d %t.o | FileCheck %s --check-prefix=CHECK-OBJ

func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    qc.h %0 : !qc.qubit
    return
}

// CHECK-ASM: main:
// CHECK-ASM: qv.h
// CHECK-OBJ: <main>:
// CHECK-OBJ: qv.h
