// RUN: qcc --target=hisepq --qubit-element-width=16 --compile-to=mlir %s | FileCheck %s

// The vectorization factor `qvec-merge` is allowed to reach is the machine's capacity, so that it never builds an
// operation wider than the QV instructions can address.
//
// At the default VLEN of 64 and a QEW of 16, the widest register group (LMUL 8, `vector<[32]xi16>`) addresses
// `8 * 64/64 * 64/16 = 32` qubits. The forty gates below are all independent, so without a cap they would merge into
// one operation on forty qubits, which no register group holds and the lowering would have to reject.

func.func @main() attributes { qcc.entry_point } {
    %q0 = qc.static 0 : !qc.qubit
    %q1 = qc.static 1 : !qc.qubit
    %q2 = qc.static 2 : !qc.qubit
    %q3 = qc.static 3 : !qc.qubit
    %q4 = qc.static 4 : !qc.qubit
    %q5 = qc.static 5 : !qc.qubit
    %q6 = qc.static 6 : !qc.qubit
    %q7 = qc.static 7 : !qc.qubit
    %q8 = qc.static 8 : !qc.qubit
    %q9 = qc.static 9 : !qc.qubit
    %q10 = qc.static 10 : !qc.qubit
    %q11 = qc.static 11 : !qc.qubit
    %q12 = qc.static 12 : !qc.qubit
    %q13 = qc.static 13 : !qc.qubit
    %q14 = qc.static 14 : !qc.qubit
    %q15 = qc.static 15 : !qc.qubit
    %q16 = qc.static 16 : !qc.qubit
    %q17 = qc.static 17 : !qc.qubit
    %q18 = qc.static 18 : !qc.qubit
    %q19 = qc.static 19 : !qc.qubit
    %q20 = qc.static 20 : !qc.qubit
    %q21 = qc.static 21 : !qc.qubit
    %q22 = qc.static 22 : !qc.qubit
    %q23 = qc.static 23 : !qc.qubit
    %q24 = qc.static 24 : !qc.qubit
    %q25 = qc.static 25 : !qc.qubit
    %q26 = qc.static 26 : !qc.qubit
    %q27 = qc.static 27 : !qc.qubit
    %q28 = qc.static 28 : !qc.qubit
    %q29 = qc.static 29 : !qc.qubit
    %q30 = qc.static 30 : !qc.qubit
    %q31 = qc.static 31 : !qc.qubit
    %q32 = qc.static 32 : !qc.qubit
    %q33 = qc.static 33 : !qc.qubit
    %q34 = qc.static 34 : !qc.qubit
    %q35 = qc.static 35 : !qc.qubit
    %q36 = qc.static 36 : !qc.qubit
    %q37 = qc.static 37 : !qc.qubit
    %q38 = qc.static 38 : !qc.qubit
    %q39 = qc.static 39 : !qc.qubit

    qc.h %q0 : !qc.qubit
    qc.h %q1 : !qc.qubit
    qc.h %q2 : !qc.qubit
    qc.h %q3 : !qc.qubit
    qc.h %q4 : !qc.qubit
    qc.h %q5 : !qc.qubit
    qc.h %q6 : !qc.qubit
    qc.h %q7 : !qc.qubit
    qc.h %q8 : !qc.qubit
    qc.h %q9 : !qc.qubit
    qc.h %q10 : !qc.qubit
    qc.h %q11 : !qc.qubit
    qc.h %q12 : !qc.qubit
    qc.h %q13 : !qc.qubit
    qc.h %q14 : !qc.qubit
    qc.h %q15 : !qc.qubit
    qc.h %q16 : !qc.qubit
    qc.h %q17 : !qc.qubit
    qc.h %q18 : !qc.qubit
    qc.h %q19 : !qc.qubit
    qc.h %q20 : !qc.qubit
    qc.h %q21 : !qc.qubit
    qc.h %q22 : !qc.qubit
    qc.h %q23 : !qc.qubit
    qc.h %q24 : !qc.qubit
    qc.h %q25 : !qc.qubit
    qc.h %q26 : !qc.qubit
    qc.h %q27 : !qc.qubit
    qc.h %q28 : !qc.qubit
    qc.h %q29 : !qc.qubit
    qc.h %q30 : !qc.qubit
    qc.h %q31 : !qc.qubit
    qc.h %q32 : !qc.qubit
    qc.h %q33 : !qc.qubit
    qc.h %q34 : !qc.qubit
    qc.h %q35 : !qc.qubit
    qc.h %q36 : !qc.qubit
    qc.h %q37 : !qc.qubit
    qc.h %q38 : !qc.qubit
    qc.h %q39 : !qc.qubit

    return
}

// Two instructions instead: a full one and the remainder.
// CHECK:      llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}) : (vector<[32]xi16>, i32, i32, i32) -> ()
// CHECK:      llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}) : (vector<[8]xi16>, i32, i32, i32) -> ()
// CHECK-NOT:  llvm.call_intrinsic
