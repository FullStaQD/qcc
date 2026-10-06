// RUN: qcc --target=hisepq --min-vlen=64 --qubit-element-width=8 --compile-to=native %s | FileCheck %s

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
// CHECK:           vsetivli    zero, 1, e8, mf4, ta, ma
// CHECK:           vmv.v.i    [[V1:v[0-9]+]], 1
// CHECK:           qv.h    [[V1]], zero, 0
// The outcome is read from `qv.mres`.
// CHECK-NEXT:      qv.mz   [[V1]], {{.*}}, 0
// CHECK-NEXT:      csrr    [[R:a[0-9]+]], qv.mres
// CHECK-NEXT:      andi    [[R]], [[R]], 1
// CHECK-NEXT:      beqz    [[R]], [[RET:\.L[a-zA-Z0-9_]+]]
// CHECK-NEXT:      qv.x    [[V1]], zero, 0
// CHECK-NEXT:  [[RET]]:
// CHECK:           ret
