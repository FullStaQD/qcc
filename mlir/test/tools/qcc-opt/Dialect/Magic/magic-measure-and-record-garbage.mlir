// RUN: qcc-opt %s --magic-measure-and-record-garbage --split-input-file | FileCheck %s

!a  = !magic.ion_chain<0, [0:1, 1:1]>
!b  = !magic.ion_chain<1, [2:1, 3:1]>
!as = !magic.ion_chain<0, [1:1]>
!bs = !magic.ion_chain<1, [0:1, 2:1, 3:1]>

// Trap 0 is not measured and the results of ions 2 and 3 are not recorded. Trap 0 gets a measurement after the last
// magic op. The missing records come after the record of the program, ordered by ion id, and are marked as garbage.
// CHECK-LABEL: func.func @partly_observed
func.func @partly_observed() {
  %a0, %b0 = magic.init : !a, !b
  %a1, %b1 = magic.shuttle %a0, %b0 : !a, !b -> !as, !bs
  %m0, %m2, %m3 = magic.mzd %b1 : !bs -> i1, i1, i1
  aux.record_int %m0 : i1
  return
}

// CHECK:      %[[A:.*]], %[[B:.*]] = magic.shuttle
// CHECK-NEXT: %[[MB:.*]]:3 = magic.mzd %[[B]] : !{{.*}} -> i1, i1, i1
// CHECK-NEXT: %[[MA:.*]] = magic.mzd %[[A]] : !{{.*}} -> i1
// CHECK-NEXT: aux.record_int %[[MB]]#0 : i1
// CHECK-NEXT: aux.record_int %[[MA]] {magic.garbage_result} : i1
// CHECK-NEXT: aux.record_int %[[MB]]#1 {magic.garbage_result} : i1
// CHECK-NEXT: aux.record_int %[[MB]]#2 {magic.garbage_result} : i1
// CHECK-NEXT: return

// -----

!a  = !magic.ion_chain<0, [0:1, 1:1]>
!b  = !magic.ion_chain<1, []>

// Everything is measured and recorded, and the empty trap 1 has nothing to measure: no change.
// CHECK-LABEL: func.func @complete
func.func @complete() {
  %a0, %b0 = magic.init : !a, !b
  %m0, %m1 = magic.mzd %a0 : !a -> i1, i1
  aux.record_int %m1 : i1
  aux.record_int %m0 : i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init
// CHECK-NEXT: %[[M:.*]]:2 = magic.mzd %[[INIT]]#0
// CHECK-NEXT: aux.record_int %[[M]]#1 : i1
// CHECK-NEXT: aux.record_int %[[M]]#0 : i1
// CHECK-NEXT: return

// -----

// A function without magic ops is left alone.
// CHECK-LABEL: func.func @no_magic
// CHECK-NEXT:    return
func.func @no_magic() {
  return
}
