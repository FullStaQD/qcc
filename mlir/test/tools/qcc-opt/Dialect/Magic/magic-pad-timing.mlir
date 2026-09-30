// RUN: qcc-opt %s --magic-pad-timing --split-input-file | FileCheck %s

!t0  = !magic.ion_chain<0, [0:1, 1:1]>
!t1  = !magic.ion_chain<1, [2:1]>
!t0s = !magic.ion_chain<0, [1:1]>
!t1s = !magic.ion_chain<1, [0:1, 2:1]>

// The example program of the dialect without its padding. Before the shuttle trap 1 idles while trap 0 waits 2491
// ticks, after it trap 0 idles while trap 1 waits 4982: each idle trap gets its ions switched off, one delay and its
// ions back on, at the end of the segment.
// CHECK-LABEL: func.func @main
func.func @main() attributes {qcc.entry_point} {
  %a0, %b0 = magic.init : !t0, !t1
  %a1 = magic.sym_zxz %a0 ions [0] {z = [1.5708], x = [1.5708]} : !t0
  %a2 = magic.delay %a1 {ticks = 2491} : !t0
  %a3 = magic.rz %a2 ions [0, 1] {angles = [-1.5708, -1.5708]} : !t0
  %a4, %b4 = magic.shuttle %a3, %b0 : !t0, !t1 -> !t0s, !t1s
  %b5 = magic.sym_zxz %b4 ions [0] {z = [0.0], x = [3.1416]} : !t1s
  %b6 = magic.delay %b5 {ticks = 4982} : !t1s
  %m0 = magic.mzd %a4 : !t0s -> i1
  %m1, %m2 = magic.mzd %b6 : !t1s -> i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init : !chain, !chain1
// CHECK-NEXT: %[[A1:.*]] = magic.sym_zxz %[[INIT]]#0
// CHECK-NEXT: %[[A2:.*]] = magic.delay %[[A1]] {ticks = 2491 : i64} : !chain
// CHECK-NEXT: %[[A3:.*]] = magic.rz %[[A2]]
// CHECK-NEXT: %[[B1:.*]] = magic.recode %[[INIT]]#1 : !chain1 -> !chain2
// CHECK-NEXT: %[[B2:.*]] = magic.delay %[[B1]] {ticks = 2491 : i64} : !chain2
// CHECK-NEXT: %[[B3:.*]] = magic.recode %[[B2]] : !chain2 -> !chain1
// CHECK-NEXT: %[[A4:.*]], %[[B4:.*]] = magic.shuttle %[[A3]], %[[B3]] : !chain, !chain1 -> !chain3, !chain4
// CHECK-NEXT: %[[B5:.*]] = magic.sym_zxz %[[B4]]
// CHECK-NEXT: %[[B6:.*]] = magic.delay %[[B5]] {ticks = 4982 : i64} : !chain4
// CHECK-NEXT: %[[A5:.*]] = magic.recode %[[A4]] : !chain3 -> !chain5
// CHECK-NEXT: %[[A6:.*]] = magic.delay %[[A5]] {ticks = 4982 : i64} : !chain5
// CHECK-NEXT: %[[A7:.*]] = magic.recode %[[A6]] : !chain5 -> !chain3
// CHECK-NEXT: magic.mzd %[[A7]] : !chain3 -> i1
// CHECK-NEXT: magic.mzd %[[B6]] : !chain4 -> i1, i1

// -----

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, []>
!c = !magic.ion_chain<2, [2:1]>
!ci = !magic.ion_chain<2, [2:0]>

// Three traps: the empty trap 1 gets nothing, trap 2 has no active ion and only waits.
// CHECK-LABEL: func.func @empty_and_inactive
func.func @empty_and_inactive() {
  %a0, %b0, %c0 = magic.init : !a, !b, !c
  %c1 = magic.recode %c0 : !c -> !ci
  %a1 = magic.delay %a0 {ticks = 7} : !a
  %m0, %m1 = magic.mzd %a1 : !a -> i1, i1
  %m2 = magic.mzd %c1 : !ci -> i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      %[[INIT:.*]]:3 = magic.init
// CHECK-NEXT: %[[C1:.*]] = magic.recode %[[INIT]]#2
// CHECK-NEXT: %[[A1:.*]] = magic.delay %[[INIT]]#0 {ticks = 7 : i64}
// CHECK-NEXT: magic.mzd %[[A1]]
// CHECK-NEXT: %[[C2:.*]] = magic.delay %[[C1]] {ticks = 7 : i64}
// CHECK-NEXT: magic.mzd %[[C2]]
// CHECK-NOT:  magic.
