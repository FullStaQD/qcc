// RUN: qcc --target=hisepq --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-DEFAULT
// RUN: qcc --target=hisepq -mattr=+zvl128b --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-VLEN128
// RUN: qcc --target=hisepq -mattr=+zvl512b --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-VLEN512
// RUN: qcc --target=hisepq -mattr=+qew16 --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-QEW16
// RUN: qcc --target=hisepq -mattr=+zvl512b,+qew16 --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-BOTH

// `zvl<N>b` also reaches the backend, so that both ends reason about the same machine. Other extensions imply a
// bound of their own, hence `zvl128b` showing up even at the default of 64.
// RUN: qcc --target=hisepq -mattr=+zvl512b --compile-to=native %s | FileCheck %s --check-prefix=CHECK-ASM

// Only the listed features exist; there is no `zvl100b`, `zvl32b` or `qew32`.
// RUN: not qcc --target=hisepq -mattr=+zvl100b --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-BAD-VLEN
// RUN: not qcc --target=hisepq -mattr=+zvl32b --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-SMALL-VLEN
// RUN: not qcc --target=hisepq -mattr=+qew32 --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-BAD-QEW
// RUN: not qcc --target=hisepq -mattr=+zvl128b,+v --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-UNKNOWN

// The machine the HiSEP-Q target lowers for is described by two features. They pick the register group the qubit
// indices travel in, so the same program comes out in a different vector type for each machine.

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
// CHECK-BOTH:     llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}) : (vector<[1]xi16>, i32, i32, i32) -> ()

// TODO: `+qew16` gets this far but not past instruction selection: the fork's QV patterns cover the
// i8 element types only (`SupportedQVVTypes` in RISCVInstrFormatsXQV.td). Hence no native RUN line for it.

// CHECK-ASM: .attribute 5, "{{.*}}_zvl512b{{.*}}_xqv0p1"

// CHECK-BAD-VLEN:   error: unknown feature '+zvl100b' for --target=hisepq
// CHECK-SMALL-VLEN: error: unknown feature '+zvl32b' for --target=hisepq
// CHECK-BAD-QEW:    error: unknown feature '+qew32' for --target=hisepq
// CHECK-UNKNOWN:    error: unknown feature '+v' for --target=hisepq
