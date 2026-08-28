// RUN: qcc --target=hisepq --compile-to=native %s | FileCheck %s

// Exercising control flow constructs
func.func @main() attributes { qcc.entry_point } {
    %1 = qc.static 1 : !qc.qubit
    qc.h %1 : !qc.qubit

    %m1 = qc.measure %1 : !qc.qubit -> i1
    scf.if %m1 {
        qc.x %1 : !qc.qubit
    }

    return
}

// CHECK-LABEL: main:
// CHECK:           vsetvli    {{.*}}, zero, e8, m1, ta, ma
// CHECK:           vmv.v.i    [[V1:v[0-9]+]], 1
// CHECK:           li    [[AVL:a[0-9]+]], 1
// CHECK:           vsetvli    zero, [[AVL]], e8, m1, ta, ma
// CHECK:           qv.h    [[V1]], zero, 0
// TODO: qv.mz and bnez are not connected so far. ISA spec says that
// hardware leaves this unimplemented. Also unclear how to exactly handle the
// measurement-halt-resume protocol.
// Related issue: https://github.com/caps-tum/HiSEP-Q-2.0/issues/8
// CHECK:           qv.mz   [[V1]], {{.*}}, 0
// CHECK:           bnez    {{.*}}, [[RET:\.L[a-zA-Z0-9_]+]]
// CHECK:           qv.x    [[V1]], zero, 0
// CHECK:       [[RET]]:
// CHECK:           ret
