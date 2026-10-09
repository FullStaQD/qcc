// `generic` drives 256 lines; -mqcl overrides that.
// RUN: qcc --target=hisepq --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-QEW8
// RUN: not qcc --target=hisepq -mqcl=8 --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-EIGHT
// RUN: qcc --target=hisepq -mqcl=9 --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-QEW8
// RUN: qcc --target=hisepq -mqubit-control-lines=9 --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-QEW8
// RUN: not qcc --target=hisepq -mqcl=0 %s 2>&1 | FileCheck %s --check-prefix=CHECK-NONE

// QELEN bounds the line count: 8-bit qubit indices address 256 lines, `xqve16` raises that to 65536.
// RUN: not qcc --target=hisepq -mqcl=257 %s 2>&1 | FileCheck %s --check-prefix=CHECK-QELEN8
// RUN: not qcc --target=hisepq -mattr=+xqve8 -mqcl=257 %s 2>&1 | FileCheck %s --check-prefix=CHECK-QELEN8
// RUN: qcc --target=hisepq -mattr=+xqve16 -mqcl=257 --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-QEW16
// RUN: not qcc --target=hisepq -mattr=+xqve16 -mqcl=65537 %s 2>&1 | FileCheck %s --check-prefix=CHECK-QELEN16

// As for `zvl<N>b`: the largest `xqve<N>` wins, and `-xqve<N>` also drops every larger one. `generic` enables `xqve8`.
// RUN: not qcc --target=hisepq -mattr=+xqve16,-xqve16 -mqcl=257 %s 2>&1 | FileCheck %s --check-prefix=CHECK-QELEN8
// RUN: qcc --target=hisepq -mattr=+xqve16,+xqve8 -mqcl=257 --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-QEW16
// RUN: not qcc --target=hisepq -mattr=+xqve16,-xqve8 %s 2>&1 | FileCheck %s --check-prefix=CHECK-NO-QELEN

// QEW stays the narrowest width addressing every line, even when QELEN allows more.
// RUN: qcc --target=hisepq -mattr=+xqve16 -mqcl=9 --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-QEW8

func.func @main() attributes { qcc.entry_point } {
    %q8 = qc.static 8 : !qc.qubit
    qc.h %q8 : !qc.qubit
    return
}

// CHECK-EIGHT:   error: 'qvec.single' op qubit index 8 exceeds the maximum of 7 for 8 qubit control lines
// CHECK-NONE:    error: -mqcl expects 1 to 256 qubit control lines for a QELEN of 8, got 0
// CHECK-QELEN8:  error: -mqcl expects 1 to 256 qubit control lines for a QELEN of 8, got 257 (16-bit qubit indices need -mattr=+xqve16)
// CHECK-NO-QELEN: error: -mcpu and -mattr leave no 'xqve<N>' feature enabled
// CHECK-QELEN16: error: -mqcl expects 1 to 65536 qubit control lines for a QELEN of 16, got 65537
// CHECK-QEW8:    llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}) : (vector<[{{[0-9]+}}]xi8>
// CHECK-QEW16:   llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}) : (vector<[{{[0-9]+}}]xi16>
