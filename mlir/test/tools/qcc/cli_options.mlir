// Exercises the qcc driver's --target / --compile-to / --binary option surface.

// Stage selection:
// RUN: qcc --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-MLIR
// RUN: qcc --compile-to=llvmir %s | FileCheck %s --check-prefix=CHECK-LLVM
// Default is LLVM-IR:
// RUN: qcc %s | FileCheck %s --check-prefix=CHECK-LLVM

// Binary encodings round-trip back to the matching textual form:
// RUN: qcc --binary --compile-to=llvmir %s -o %t.bc
// RUN: llvm-dis %t.bc -o - | FileCheck %s --check-prefix=CHECK-LLVM
// RUN: qcc --binary --compile-to=mlir %s -o %t.mlirbc
// RUN: qcc-opt %t.mlirbc | FileCheck %s --check-prefix=CHECK-MLIR

// The default target (qir) is always available:
// RUN: qcc --target=qir %s | FileCheck %s --check-prefix=CHECK-LLVM

// Invalid / unimplemented option combinations are hard errors:
// RUN: not qcc --target=does-not-exist %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-UNKNOWN
// RUN: not qcc --compile-to=native %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-NATIVE

func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    qc.h %0 : !qc.qubit
    %m0 = qc.measure %0 : !qc.qubit -> i1
    aux.record_int %m0 : i1
    return
}

// CHECK-MLIR: llvm.func @main()
// CHECK-LLVM: define void @main()
// CHECK-ERR-UNKNOWN: error: unknown target 'does-not-exist'
// CHECK-ERR-NATIVE: error: the 'native' stage is not yet implemented
