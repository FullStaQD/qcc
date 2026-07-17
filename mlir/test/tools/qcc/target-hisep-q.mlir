// REQUIRES: hisep-q

// RUN: qcc --list-targets | FileCheck %s --check-prefix=CHECK-LIST
// RUN: qcc --target=hisep-q --compile-to=mlir %s | FileCheck %s

// CHECK-LIST: hisep-q - HiSEP-Q QISA target
// CHECK: func.func @main

// TODO: this is a stub, updated once we have implemented the hisep-q target.
func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    qc.h %0 : !qc.qubit
    return
}
