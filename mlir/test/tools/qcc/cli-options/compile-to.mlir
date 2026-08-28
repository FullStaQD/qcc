// RUN: qcc --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-MLIR
// RUN: qcc --compile-to=llvmir %s | FileCheck %s --check-prefix=CHECK-LLVM
// Default is LLVM-IR:
// RUN: qcc %s | FileCheck %s --check-prefix=CHECK-LLVM

func.func @main() attributes { qcc.entry_point } {
    return
}

// CHECK-MLIR: llvm.func @main()
// CHECK-LLVM: define void @main()
