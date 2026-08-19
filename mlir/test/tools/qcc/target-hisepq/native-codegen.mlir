// RUN: qcc --target=hisepq --compile-to=native %s | FileCheck %s

func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    qc.h %0 : !qc.qubit
    return
}

// CHECK: main:
// CHECK: qv.h

// `_start` is the synthesized boot entry point (see hisepq.ld): it sets up the stack and calls
// `main`, so it must also show up in native output.
// CHECK: _start:
