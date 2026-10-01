// RUN: qcc-opt %s --magic-pad-timing --split-input-file | FileCheck %s

!t0  = !magic.ion_chain<0, [0:1, 1:1]>
!t1  = !magic.ion_chain<1, [2:1]>
!t0s = !magic.ion_chain<0, [1:1]>
!t1s = !magic.ion_chain<1, [0:1, 2:1]>

// Trap 0 waits before the shuttle, so trap 1 is padded there, with its ion switched off. What trap 1 does after the
// shuttle needs no padding: the measurement is no sync point.
// CHECK:       !chain2 = !magic.ion_chain<1, [2:0]>
// CHECK-LABEL: func.func @pad_before_shuttle
func.func @pad_before_shuttle() {
  %a0, %b0 = magic.init : !t0, !t1
  %a1 = magic.delay %a0 {ticks = 2491} : !t0
  %a2, %b1 = magic.shuttle %a1, %b0 : !t0, !t1 -> !t0s, !t1s
  %b2 = magic.delay %b1 {ticks = 4982} : !t1s
  %m0 = magic.mzd %a2 : !t0s -> i1
  %m1, %m2 = magic.mzd %b2 : !t1s -> i1, i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init : !chain, !chain1
// CHECK-NEXT: %[[A1:.*]] = magic.delay %[[INIT]]#0 {ticks = 2491 : i64} : !chain
// CHECK-NEXT: %[[B1:.*]] = magic.recode %[[INIT]]#1 : !chain1 -> !chain2
// CHECK-NEXT: %[[B2:.*]] = magic.delay %[[B1]] {ticks = 2491 : i64} : !chain2
// CHECK-NEXT: %[[B3:.*]] = magic.recode %[[B2]] : !chain2 -> !chain1
// CHECK-NEXT: %[[A2:.*]], %[[B4:.*]] = magic.shuttle %[[A1]], %[[B3]] : !chain, !chain1 -> !chain3, !chain4
// CHECK-NEXT: %[[B5:.*]] = magic.delay %[[B4]] {ticks = 4982 : i64} : !chain4
// CHECK-NEXT: magic.mzd %[[A2]] : !chain3 -> i1
// CHECK-NEXT: magic.mzd %[[B5]] : !chain4 -> i1, i1

// -----

!a  = !magic.ion_chain<0, [0:1, 1:1]>
!b  = !magic.ion_chain<1, [2:1]>
!as = !magic.ion_chain<0, [1:1]>
!bs = !magic.ion_chain<1, [0:1, 2:1]>
!c  = !magic.ion_chain<2, [3:1]>

// A shuttle syncs its two traps only. Trap 0 and trap 1 take turns in being behind; trap 2 takes no part and is left
// alone, although it has spent no time at all.
// CHECK-LABEL: func.func @uninvolved_trap
func.func @uninvolved_trap() {
  %a0, %b0, %c0 = magic.init : !a, !b, !c
  %a1 = magic.delay %a0 {ticks = 5} : !a
  %a2, %b1 = magic.shuttle %a1, %b0 : !a, !b -> !as, !bs
  %b2 = magic.delay %b1 {ticks = 7} : !bs
  %b3, %a3 = magic.shuttle %b2, %a2 : !bs, !as -> !b, !a
  %m0, %m1 = magic.mzd %a3 : !a -> i1, i1
  %m2 = magic.mzd %b3 : !b -> i1
  %m3 = magic.mzd %c0 : !c -> i1
  return
}

// CHECK:      %[[INIT:.*]]:3 = magic.init
// CHECK-NEXT: %[[A1:.*]] = magic.delay %[[INIT]]#0 {ticks = 5 : i64}
// CHECK-NEXT: %[[B1:.*]] = magic.recode %[[INIT]]#1
// CHECK-NEXT: %[[B2:.*]] = magic.delay %[[B1]] {ticks = 5 : i64}
// CHECK-NEXT: %[[B3:.*]] = magic.recode %[[B2]]
// CHECK-NEXT: %[[A2:.*]], %[[B4:.*]] = magic.shuttle %[[A1]], %[[B3]]
// CHECK-NEXT: %[[B5:.*]] = magic.delay %[[B4]] {ticks = 7 : i64}
// CHECK-NEXT: %[[A3:.*]] = magic.recode %[[A2]]
// CHECK-NEXT: %[[A4:.*]] = magic.delay %[[A3]] {ticks = 7 : i64}
// CHECK-NEXT: %[[A5:.*]] = magic.recode %[[A4]]
// CHECK-NEXT: %[[B6:.*]], %[[A6:.*]] = magic.shuttle %[[B5]], %[[A5]]
// CHECK-NEXT: magic.mzd %[[A6]]
// CHECK-NEXT: magic.mzd %[[B6]]
// CHECK-NEXT: magic.mzd %[[INIT]]#2

// -----

!a  = !magic.ion_chain<0, [0:1, 1:1]>
!b  = !magic.ion_chain<1, []>
!as = !magic.ion_chain<0, [1:1]>
!bs = !magic.ion_chain<1, [0:1]>

// An empty trap that receives an ion is padded as well, by a plain delay: there is no ion to switch off.
// CHECK-LABEL: func.func @empty_destination
func.func @empty_destination() {
  %a0, %b0 = magic.init : !a, !b
  %a1 = magic.delay %a0 {ticks = 7} : !a
  %a2, %b1 = magic.shuttle %a1, %b0 : !a, !b -> !as, !bs
  %m0 = magic.mzd %a2 : !as -> i1
  %m1 = magic.mzd %b1 : !bs -> i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init
// CHECK-NEXT: %[[A1:.*]] = magic.delay %[[INIT]]#0 {ticks = 7 : i64}
// CHECK-NEXT: %[[B1:.*]] = magic.delay %[[INIT]]#1 {ticks = 7 : i64}
// CHECK-NEXT: %[[A2:.*]], %[[B2:.*]] = magic.shuttle %[[A1]], %[[B1]]
// CHECK-NEXT: magic.mzd %[[A2]]
// CHECK-NEXT: magic.mzd %[[B2]]
