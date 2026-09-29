// RUN: not qcc --target=hisepq --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-DEFAULT
// RUN: qcc --target=hisepq -mattr=+qcl16 --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-FITS
// RUN: qcc --target=hisepq -mattr=+qcl128,-qcl32 --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-FITS
// RUN: not qcc --target=hisepq -mattr=+qcl128,-qcl16 --compile-to=mlir %s 2>&1 \
// RUN:   | FileCheck %s --check-prefix=CHECK-DEFAULT

// RUN: not qcc --target=hisepq -mattr=-qcl8 %s 2>&1 | FileCheck %s --check-prefix=CHECK-NONE

// 256 is all 8-bit indices address.
// RUN: not qcc --target=hisepq -mattr=+qcl512 %s 2>&1 | FileCheck %s --check-prefix=CHECK-TOO-MANY

func.func @main() attributes { qcc.entry_point } {
    %q8 = qc.static 8 : !qc.qubit
    qc.h %q8 : !qc.qubit
    return
}

// CHECK-DEFAULT:  error: 'qvec.single' op qubit index 8 exceeds the maximum of 7 for 8 qubit control lines
// CHECK-FITS:     llvm.call_intrinsic "llvm.riscv.qv.h"
// CHECK-NONE:     error: -mcpu and -mattr leave no 'qcl<N>' feature enabled
// CHECK-TOO-MANY: error: unknown feature '+qcl512' for --target=hisepq
