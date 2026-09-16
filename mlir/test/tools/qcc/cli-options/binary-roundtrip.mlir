// RUN: qcc --binary --compile-to=mlir %s -o %t.mlirbc
// RUN: qcc-opt %t.mlirbc | FileCheck %s --check-prefix=CHECK-MLIR

// RUN: qcc --binary --compile-to=llvmir %s -o %t.bc
// RUN: llvm-dis %t.bc -o - | FileCheck %s --check-prefix=CHECK-LLVM

func.func @main() attributes { qcc.entry_point } {
    return
}

// CHECK-MLIR: llvm.func @main()
// CHECK-LLVM: define void @main()
