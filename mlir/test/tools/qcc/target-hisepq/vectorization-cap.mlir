// RUN: qcc --target=hisepq -mattr=+zvl64b,+xqvel16b -mqcl=300 --compile-to=mlir %s | FileCheck %s


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

    %m0 = qc.measure %q0 : !qc.qubit -> i1
    %m1 = qc.measure %q1 : !qc.qubit -> i1
    %m2 = qc.measure %q2 : !qc.qubit -> i1
    %m3 = qc.measure %q3 : !qc.qubit -> i1
    %m4 = qc.measure %q4 : !qc.qubit -> i1
    %m5 = qc.measure %q5 : !qc.qubit -> i1
    %m6 = qc.measure %q6 : !qc.qubit -> i1
    %m7 = qc.measure %q7 : !qc.qubit -> i1
    %m8 = qc.measure %q8 : !qc.qubit -> i1
    %m9 = qc.measure %q9 : !qc.qubit -> i1
    %m10 = qc.measure %q10 : !qc.qubit -> i1
    %m11 = qc.measure %q11 : !qc.qubit -> i1
    %m12 = qc.measure %q12 : !qc.qubit -> i1
    %m13 = qc.measure %q13 : !qc.qubit -> i1
    %m14 = qc.measure %q14 : !qc.qubit -> i1
    %m15 = qc.measure %q15 : !qc.qubit -> i1
    %m16 = qc.measure %q16 : !qc.qubit -> i1
    %m17 = qc.measure %q17 : !qc.qubit -> i1
    %m18 = qc.measure %q18 : !qc.qubit -> i1
    %m19 = qc.measure %q19 : !qc.qubit -> i1
    %m20 = qc.measure %q20 : !qc.qubit -> i1
    %m21 = qc.measure %q21 : !qc.qubit -> i1
    %m22 = qc.measure %q22 : !qc.qubit -> i1
    %m23 = qc.measure %q23 : !qc.qubit -> i1
    %m24 = qc.measure %q24 : !qc.qubit -> i1
    %m25 = qc.measure %q25 : !qc.qubit -> i1
    %m26 = qc.measure %q26 : !qc.qubit -> i1
    %m27 = qc.measure %q27 : !qc.qubit -> i1
    %m28 = qc.measure %q28 : !qc.qubit -> i1
    %m29 = qc.measure %q29 : !qc.qubit -> i1
    %m30 = qc.measure %q30 : !qc.qubit -> i1
    %m31 = qc.measure %q31 : !qc.qubit -> i1
    %m32 = qc.measure %q32 : !qc.qubit -> i1
    %m33 = qc.measure %q33 : !qc.qubit -> i1
    %m34 = qc.measure %q34 : !qc.qubit -> i1
    %m35 = qc.measure %q35 : !qc.qubit -> i1
    %m36 = qc.measure %q36 : !qc.qubit -> i1
    %m37 = qc.measure %q37 : !qc.qubit -> i1
    %m38 = qc.measure %q38 : !qc.qubit -> i1
    %m39 = qc.measure %q39 : !qc.qubit -> i1

    aux.record_int %m0 : i1
    aux.record_int %m1 : i1
    aux.record_int %m2 : i1
    aux.record_int %m3 : i1
    aux.record_int %m4 : i1
    aux.record_int %m5 : i1
    aux.record_int %m6 : i1
    aux.record_int %m7 : i1
    aux.record_int %m8 : i1
    aux.record_int %m9 : i1
    aux.record_int %m10 : i1
    aux.record_int %m11 : i1
    aux.record_int %m12 : i1
    aux.record_int %m13 : i1
    aux.record_int %m14 : i1
    aux.record_int %m15 : i1
    aux.record_int %m16 : i1
    aux.record_int %m17 : i1
    aux.record_int %m18 : i1
    aux.record_int %m19 : i1
    aux.record_int %m20 : i1
    aux.record_int %m21 : i1
    aux.record_int %m22 : i1
    aux.record_int %m23 : i1
    aux.record_int %m24 : i1
    aux.record_int %m25 : i1
    aux.record_int %m26 : i1
    aux.record_int %m27 : i1
    aux.record_int %m28 : i1
    aux.record_int %m29 : i1
    aux.record_int %m30 : i1
    aux.record_int %m31 : i1
    aux.record_int %m32 : i1
    aux.record_int %m33 : i1
    aux.record_int %m34 : i1
    aux.record_int %m35 : i1
    aux.record_int %m36 : i1
    aux.record_int %m37 : i1
    aux.record_int %m38 : i1
    aux.record_int %m39 : i1

    return
}

// Two instructions instead: a full one and the remainder.
// CHECK:      llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}) : (vector<[32]xi16>, i32, i32, i32) -> ()
// CHECK:      llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}) : (vector<[8]xi16>, i32, i32, i32) -> ()
// CHECK-NOT:  llvm.call_intrinsic "llvm.riscv.qv.h"
