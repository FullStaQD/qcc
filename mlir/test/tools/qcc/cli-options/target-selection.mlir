// RUN: qcc --target=qir %s | FileCheck %s --check-prefix=CHECK-LLVM
// RUN: not qcc --target=does-not-exist %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-UNKNOWN
// The default target (qir) has no native backend, so --compile-to=native fails:
// RUN: not qcc --compile-to=native %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-NATIVE
// It has no use for the machine parameters either, and says so rather than ignoring them:
// RUN: not qcc --target=qir --min-vlen=128 %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-VLEN
// RUN: not qcc --target=qir --qubit-element-width=16 %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-QEW

func.func @main() attributes { qcc.entry_point } {
    return
}

// CHECK-MLIR: llvm.func @main()
// CHECK-LLVM: define void @main()

// CHECK-ERR-UNKNOWN: error: unknown target 'does-not-exist'
// CHECK-ERR-NATIVE: error: native output is not supported for --target=qir
// CHECK-ERR-VLEN: error: --min-vlen is not supported for --target=qir
// CHECK-ERR-QEW: error: --qubit-element-width is not supported for --target=qir
