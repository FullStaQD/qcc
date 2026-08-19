// RUN: qcc --target=qir %s | FileCheck %s --check-prefix=CHECK-LLVM
// RUN: not qcc --target=does-not-exist %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-UNKNOWN
// The default target (qir) has no native backend, so --compile-to=native fails:
// RUN: not qcc --compile-to=native %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-NATIVE

func.func @main() attributes { qcc.entry_point } {
    return
}

// CHECK-MLIR: llvm.func @main()
// CHECK-LLVM: define void @main()

// CHECK-ERR-UNKNOWN: error: unknown target 'does-not-exist'
// CHECK-ERR-NATIVE: error: native output is not supported for --target=qir
