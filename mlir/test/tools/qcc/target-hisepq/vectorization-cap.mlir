// RUN: qcc --target=hisepq -mattr=+qcl128 --compile-to=mlir %s | FileCheck %s

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
    %q40 = qc.static 40 : !qc.qubit
    %q41 = qc.static 41 : !qc.qubit
    %q42 = qc.static 42 : !qc.qubit
    %q43 = qc.static 43 : !qc.qubit
    %q44 = qc.static 44 : !qc.qubit
    %q45 = qc.static 45 : !qc.qubit
    %q46 = qc.static 46 : !qc.qubit
    %q47 = qc.static 47 : !qc.qubit
    %q48 = qc.static 48 : !qc.qubit
    %q49 = qc.static 49 : !qc.qubit
    %q50 = qc.static 50 : !qc.qubit
    %q51 = qc.static 51 : !qc.qubit
    %q52 = qc.static 52 : !qc.qubit
    %q53 = qc.static 53 : !qc.qubit
    %q54 = qc.static 54 : !qc.qubit
    %q55 = qc.static 55 : !qc.qubit
    %q56 = qc.static 56 : !qc.qubit
    %q57 = qc.static 57 : !qc.qubit
    %q58 = qc.static 58 : !qc.qubit
    %q59 = qc.static 59 : !qc.qubit
    %q60 = qc.static 60 : !qc.qubit
    %q61 = qc.static 61 : !qc.qubit
    %q62 = qc.static 62 : !qc.qubit
    %q63 = qc.static 63 : !qc.qubit
    %q64 = qc.static 64 : !qc.qubit
    %q65 = qc.static 65 : !qc.qubit
    %q66 = qc.static 66 : !qc.qubit
    %q67 = qc.static 67 : !qc.qubit
    %q68 = qc.static 68 : !qc.qubit
    %q69 = qc.static 69 : !qc.qubit
    %q70 = qc.static 70 : !qc.qubit
    %q71 = qc.static 71 : !qc.qubit

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
    qc.h %q40 : !qc.qubit
    qc.h %q41 : !qc.qubit
    qc.h %q42 : !qc.qubit
    qc.h %q43 : !qc.qubit
    qc.h %q44 : !qc.qubit
    qc.h %q45 : !qc.qubit
    qc.h %q46 : !qc.qubit
    qc.h %q47 : !qc.qubit
    qc.h %q48 : !qc.qubit
    qc.h %q49 : !qc.qubit
    qc.h %q50 : !qc.qubit
    qc.h %q51 : !qc.qubit
    qc.h %q52 : !qc.qubit
    qc.h %q53 : !qc.qubit
    qc.h %q54 : !qc.qubit
    qc.h %q55 : !qc.qubit
    qc.h %q56 : !qc.qubit
    qc.h %q57 : !qc.qubit
    qc.h %q58 : !qc.qubit
    qc.h %q59 : !qc.qubit
    qc.h %q60 : !qc.qubit
    qc.h %q61 : !qc.qubit
    qc.h %q62 : !qc.qubit
    qc.h %q63 : !qc.qubit
    qc.h %q64 : !qc.qubit
    qc.h %q65 : !qc.qubit
    qc.h %q66 : !qc.qubit
    qc.h %q67 : !qc.qubit
    qc.h %q68 : !qc.qubit
    qc.h %q69 : !qc.qubit
    qc.h %q70 : !qc.qubit
    qc.h %q71 : !qc.qubit

    return
}

// A full instruction at the cap, then the remainder.
// CHECK:      llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}) : (vector<[64]xi8>, i32, i32, i32) -> ()
// CHECK:      llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}) : (vector<[8]xi8>, i32, i32, i32) -> ()
// CHECK-NOT:  llvm.call_intrinsic
