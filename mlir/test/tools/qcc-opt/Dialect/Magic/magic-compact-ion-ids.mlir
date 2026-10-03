// RUN: qcc-opt %s --magic-compact-ion-ids --split-input-file | FileCheck %s

!a   = !magic.ion_chain<1, [2:1, 5:1]>
!b   = !magic.ion_chain<3, [7:1]>
!as  = !magic.ion_chain<1, [5:1]>
!bs  = !magic.ion_chain<3, [2:1, 7:1]>
!bsi = !magic.ion_chain<3, [2:1, 7:0]>

// Ions 2, 5 (trap 1) and 7 (trap 3) become ions 0, 1 and 2: numbered in the order of `magic.init`, trap by trap. The
// chain types and the ion lists follow, the trap ids stay as they are.
// CHECK-DAG:   ![[A:.*]] = !magic.ion_chain<1, [0:1, 1:1]>
// CHECK-DAG:   ![[B:.*]] = !magic.ion_chain<3, [2:1]>
// CHECK-DAG:   ![[AS:.*]] = !magic.ion_chain<1, [1:1]>
// CHECK-DAG:   ![[BS:.*]] = !magic.ion_chain<3, [0:1, 2:1]>
// CHECK-DAG:   ![[BSI:.*]] = !magic.ion_chain<3, [0:1, 2:0]>
// CHECK-LABEL: func.func @gaps
func.func @gaps() {
  %a0, %b0 = magic.init : !a, !b
  %a1 = magic.rz %a0 ions [5] {angles = [0.5]} : !a
  %a2 = magic.sym_zxz %a1 ions [2, 5] {z = [0.1, 0.2], x = [0.3, 0.4]} : !a
  %a3, %b1 = magic.shuttle %a2, %b0 : !a, !b -> !as, !bs
  %b2 = magic.recode %b1 : !bs -> !bsi
  %b3 = magic.delay %b2 {ticks = 10} : !bsi
  %m5 = magic.mzd %a3 : !as -> i1
  %m2, %m7 = magic.mzd %b3 : !bsi -> i1, i1
  aux.record_int %m7 : i1
  aux.record_int %m2 : i1
  aux.record_int %m5 : i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init : ![[A]], ![[B]]
// CHECK-NEXT: %[[A1:.*]] = magic.rz %[[INIT]]#0 ions [1] {angles = [5.000000e-01]} : ![[A]]
// CHECK-NEXT: %[[A2:.*]] = magic.sym_zxz %[[A1]] ions [0, 1] {{.*}} : ![[A]]
// CHECK-NEXT: %[[A3:.*]], %[[B1:.*]] = magic.shuttle %[[A2]], %[[INIT]]#1 : ![[A]], ![[B]] -> ![[AS]], ![[BS]]
// CHECK-NEXT: %[[B2:.*]] = magic.recode %[[B1]] : ![[BS]] -> ![[BSI]]
// CHECK-NEXT: %[[B3:.*]] = magic.delay %[[B2]] {ticks = 10 : i64} : ![[BSI]]
// CHECK-NEXT: %[[MA:.*]] = magic.mzd %[[A3]] : ![[AS]] -> i1
// CHECK-NEXT: %[[MB:.*]]:2 = magic.mzd %[[B3]] : ![[BSI]] -> i1, i1
// CHECK-NEXT: aux.record_int %[[MB]]#1 : i1
// CHECK-NEXT: aux.record_int %[[MB]]#0 : i1
// CHECK-NEXT: aux.record_int %[[MA]] : i1

// -----

!a = !magic.ion_chain<0, [4:1, 9:1]>
!b = !magic.ion_chain<1, [10:1]>

// The intermediate ops name ions as well.
// CHECK-LABEL: func.func @intermediate_ops
func.func @intermediate_ops() {
  %a0, %b0 = magic.init : !a, !b
  %a1 = magic.zxz %a0 ions [9] {z1 = [0.1], x = [0.2], z2 = [0.3]} : !a
  %a2 = magic.swap %a1 ions [4, 9] : !a
  %a3, %b1 = magic.inter_trap_zz %a2, %b0 ions [9, 10] {angle = 0.5} : !a, !b
  return
}

// CHECK:      magic.zxz %{{.*}} ions [1]
// CHECK-NEXT: magic.swap %{{.*}} ions [0, 1]
// CHECK-NEXT: magic.inter_trap_zz %{{.*}}, %{{.*}} ions [1, 2]

// -----

// Already compact: no change. A function without magic ops is left alone.
// CHECK:       !chain = !magic.ion_chain<1, [0:1, 1:1]>
// CHECK-LABEL: func.func @compact
// CHECK-NEXT:    magic.init : !chain
func.func @compact() {
  %a0 = magic.init : !magic.ion_chain<1, [0:1, 1:1]>
  return
}

// CHECK-LABEL: func.func @no_magic
// CHECK-NEXT:    return
func.func @no_magic() {
  return
}
