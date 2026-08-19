// RUN: qcc --target=hisepq --compile-to=native %s | FileCheck %s

/// Prepare GHZ state without control flow.
func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    %1 = qc.static 1 : !qc.qubit
    %2 = qc.static 2 : !qc.qubit

    qc.h %0 : !qc.qubit

    qc.ctrl(%0) { qc.x %1 : !qc.qubit } : !qc.qubit
    qc.ctrl(%1) { qc.x %2 : !qc.qubit } : !qc.qubit

    %m0 = qc.measure %0 : !qc.qubit -> i1
    %m1 = qc.measure %1 : !qc.qubit -> i1
    %m2 = qc.measure %2 : !qc.qubit -> i1

    %a = arith.constant 42 : i64

    aux.record_int %a : i64
    aux.record_int %m0 : i1
    aux.record_int %m1 : i1
    aux.record_int %m2 : i1

    return
}

// Record that we need the HiSEP-Q vendor extension (RISC-V).
// CHECK:      .attribute 5, "{{.*}}_xqv0p1"

// CHECK:      main:
// CHECK-DAG:     vsetvli  {{.*}}, zero, e8, m1, ta, ma
// CHECK-DAG:     vmv.s.x  [[V1:v[0-9]+]], zero
// CHECK-DAG:     vmv.v.i  [[V2:v[0-9]+]], 1
// CHECK-DAG:     vmv.v.i  [[V3:v[0-9]+]], 2
// CHECK-DAG:     li       [[AVL:a[0-9]+]], 1
// CHECK:         vsetvli  zero, [[AVL]], e8, m1, ta, ma
// CHECK:         qv.h     [[V1]], zero, 0
// CHECK:         qv.cx    [[V1]], [[V2]], 0
// CHECK:         qv.cx    [[V2]], [[V3]], 0
// CHECK-DAG:     qv.mz    [[V1]], zero, 0
// CHECK-DAG:     qv.mz    [[V2]], zero, 0
// CHECK-DAG:     qv.mz    [[V3]], zero, 0
// CHECK:         ret

// Two preconditions that the linker script hisepq.ld depends on silently.
// CHECK:      .section .text._start,"ax",@progbits
// CHECK:      .globl  _start

// CHECK:      _start:
// CHECK-NEXT:    lui     [[R1:a[0-9]+]], %hi(__stack_top)
// CHECK-NEXT:    addi    [[R1]], [[R1]], %lo(__stack_top)
// CHECK-NEXT:    lui     [[R2:a[0-9]+]], %hi(main)
// CHECK-NEXT:    addi    [[R2]], [[R2]], %lo(main)
// CHECK:         mv      sp, [[R1]]
// CHECK:         jalr    [[R2]]
// TODO: infinite loop correct?
// CHECK:         [[LOOP:\.Ltmp[0-9]+]]:
// CHECK:         j     [[LOOP]]
