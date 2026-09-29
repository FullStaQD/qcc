// RUN: qcc --target=hisepq --compile-to=native --binary %s -o %t.o
// RUN: llvm-objdump -d %t.o | FileCheck %s

func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    qc.h %0 : !qc.qubit
    qc.x %0 : !qc.qubit
    return
}

// Check that our stuff survives the roundtrip and does not degraded to
// `<unknown>` or re-interpreted as other instructions.
// CHECK: qv.h
// CHECK: qv.x
