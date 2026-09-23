// RUN: qcc --target=hisepq --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-DEFAULT
// RUN: qcc --target=hisepq --min-vlen=128 --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-VLEN128
// RUN: qcc --target=hisepq --min-vlen=512 --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-VLEN512
// RUN: qcc --target=hisepq --qubit-element-width=16 --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-QEW16

// `min-vlen` also reaches the backend, where RISC-V spells it `zvl<N>b`, so that both ends reason about the same
// machine. Other extensions imply a bound of their own, hence `zvl128b` showing up even at the default of 64.
// RUN: qcc --target=hisepq --min-vlen=512 --compile-to=native %s | FileCheck %s --check-prefix=CHECK-ASM

// Neither option takes just any number.
// RUN: not qcc --target=hisepq --min-vlen=100 --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-BAD-VLEN
// RUN: not qcc --target=hisepq --min-vlen=32 --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-SMALL-VLEN
// RUN: not qcc --target=hisepq --qubit-element-width=32 --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-BAD-QEW

// The machine the HiSEP-Q target lowers for is described by two options. They pick the register group the qubit
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

// TODO: `qubit-element-width=16` gets this far but not past instruction selection: the fork's QV patterns cover the
// i8 element types only (`SupportedQVVTypes` in RISCVInstrFormatsXQV.td). Hence no native RUN line for it.

// CHECK-ASM: .attribute 5, "{{.*}}_zvl512b{{.*}}_xqv0p1"

// CHECK-BAD-VLEN:   'min-vlen' expects a power of two of at least 64, got 100
// CHECK-SMALL-VLEN: 'min-vlen' expects a power of two of at least 64, got 32
// CHECK-BAD-QEW:    'qubit-element-width' expects 8 or 16, got 32
