// REQUIRES: hisep-q

// RUN: qcc --list-targets | FileCheck %s --check-prefix=CHECK-LIST
// RUN: qcc --target=hisep-q --compile-to=mlir %s | FileCheck %s

// CHECK-LIST: hisep-q - HiSEP-Q QISA target

// The HiSEP-Q lowering runs the full QIR pipeline and then replaces the QIS
// call ops with RISC-V QV intrinsics.
// CHECK-LABEL: llvm.func @main()
// CHECK-NOT:     llvm.call @__quantum__qis
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"({{.*}})
// CHECK:         llvm.return

func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    qc.h %0 : !qc.qubit
    return
}
