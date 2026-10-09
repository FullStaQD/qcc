// RUN: qcc --target=hisepq --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-DEFAULT
// RUN: qcc --target=hisepq -mcpu=generic --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-DEFAULT
// RUN: qcc --target=hisepq -mattr=+zvl128b --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-VLEN128
// RUN: qcc --target=hisepq -mattr=+zvl512b --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-VLEN512
// RUN: qcc --target=hisepq -mattr=+xqve16 -mqcl=257 --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-QEW16

// As in LLVM: a bare name enables, the largest bound wins, and `-zvl<N>b` also drops every larger one.
// RUN: qcc --target=hisepq -mattr=zvl512b --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-VLEN512
// RUN: qcc --target=hisepq -mattr=+zvl512b,+zvl128b --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-VLEN512
// RUN: qcc --target=hisepq -mattr=+zvl512b,-zvl256b --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-VLEN128
// RUN: qcc --target=hisepq -mattr=+zvl512b,-zvl128b --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-DEFAULT

// `zvl<N>b` is forwarded to the backend.
// RUN: qcc --target=hisepq -mattr=+zvl512b --compile-to=native %s | FileCheck %s --check-prefix=CHECK-ASM

// RUN: not qcc --target=hisepq -mcpu=nope %s 2>&1 | FileCheck %s --check-prefix=CHECK-BAD-CPU
// RUN: not qcc --target=hisepq -mattr=-zvl64b --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-NO-VLEN

// Only the listed features exist; there is no `zvl100b`, `zvl32b` or `qew16`.
// RUN: not qcc --target=hisepq -mattr=+zvl100b --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-BAD-VLEN
// RUN: not qcc --target=hisepq -mattr=+zvl32b --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-SMALL-VLEN
// RUN: not qcc --target=hisepq -mattr=+qew16 --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-QEW-MATTR
// RUN: not qcc --target=hisepq -mattr=+zvl128b,+v --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-UNKNOWN

func.func @main() attributes { qcc.entry_point } {
    %q0 = qc.static 0 : !qc.qubit
    %q1 = qc.static 1 : !qc.qubit
    %q2 = qc.static 2 : !qc.qubit
    %q3 = qc.static 3 : !qc.qubit
    %q4 = qc.static 4 : !qc.qubit
    %q5 = qc.static 5 : !qc.qubit
    %q6 = qc.static 6 : !qc.qubit
    %q7 = qc.static 7 : !qc.qubit

    qc.h %q0 : !qc.qubit
    qc.h %q1 : !qc.qubit
    qc.h %q2 : !qc.qubit
    qc.h %q3 : !qc.qubit
    qc.h %q4 : !qc.qubit
    qc.h %q5 : !qc.qubit
    qc.h %q6 : !qc.qubit
    qc.h %q7 : !qc.qubit

    return
}

// The eight gates merge into one instruction over eight qubits either way; what changes is how wide a register group
// that takes. A `vector<[N]xi{QEW}>` holds `N * minVLen/64` elements, so the wider the machine, the narrower the N
// that fits all eight -- and a wider QEW pushes the other way.

// CHECK-DEFAULT:  llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}) : (vector<[8]xi8>, i32, i32, i32) -> ()
// CHECK-VLEN128:  llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}) : (vector<[4]xi8>, i32, i32, i32) -> ()
// CHECK-VLEN512:  llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}) : (vector<[2]xi8>, i32, i32, i32) -> ()
// CHECK-QEW16:    llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}) : (vector<[8]xi16>, i32, i32, i32) -> ()

// TODO(#174): QEW 16 gets this far but not past instruction selection: the LLVM fork doesn't cover i16 element types.

// CHECK-ASM: .attribute 5, "{{.*}}_zvl512b{{.*}}_xqv0p1"

// CHECK-BAD-CPU: error: unknown CPU 'nope' for --target=hisepq
// CHECK-NO-VLEN: error: -mcpu and -mattr leave no 'zvl<N>b' feature enabled

// CHECK-BAD-VLEN:   error: unknown feature '+zvl100b' for --target=hisepq
// CHECK-SMALL-VLEN: error: unknown feature '+zvl32b' for --target=hisepq
// CHECK-QEW-MATTR:  error: unknown feature '+qew16' for --target=hisepq
// CHECK-UNKNOWN:    error: unknown feature '+v' for --target=hisepq
