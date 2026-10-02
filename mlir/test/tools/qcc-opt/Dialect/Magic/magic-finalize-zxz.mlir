// RUN: qcc-opt %s --magic-finalize-zxz --split-input-file --allow-unregistered-dialect | FileCheck %s

!c = !magic.ion_chain<0, [0:1, 1:1]>

// zxz(z1, x, z2) = rz(z1 + z2) after sym_zxz(z1, x); the residual rz(0.4) reaches the measurement and is dropped.
// CHECK-LABEL: func.func @rz_dropped_before_mzd
func.func @rz_dropped_before_mzd() {
  %c0 = magic.init : !c
  %c1 = magic.zxz %c0 ions [0] {z1 = [0.1], x = [0.2], z2 = [0.3]} : !c
  %m0, %m1 = magic.mzd %c1 : !c -> i1, i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init
// CHECK-NEXT: %[[C1:.*]] = magic.sym_zxz %[[C0]] ions [0] {x = [2.000000e-01], z = [1.000000e-01]} : !chain
// CHECK-NEXT: magic.mzd %[[C1]]

// -----

!c = !magic.ion_chain<0, [0:1, 1:1]>
!ci = !magic.ion_chain<0, [0:1, 1:0]>

// The residual rz(0.1 + 0.3) of the first zxz and the explicit rz(0.5) commute through the delay and the recodes and
// are absorbed into z1 of the next zxz on ion 0.
// CHECK-LABEL: func.func @rz_absorbed
func.func @rz_absorbed() {
  %c0 = magic.init : !c
  %c1 = magic.zxz %c0 ions [0] {z1 = [0.1], x = [0.2], z2 = [0.3]} : !c
  %c2 = magic.delay %c1 {ticks = 10} : !c
  %c3 = magic.recode %c2 : !c -> !ci
  %c4 = magic.rz %c3 ions [0] {angles = [0.5]} : !ci
  %c5 = magic.recode %c4 : !ci -> !c
  %c6 = magic.zxz %c5 ions [0, 1] {z1 = [0.4, 0.0], x = [0.5, 1.0], z2 = [0.6, 0.0]} : !c
  %m0, %m1 = magic.mzd %c6 : !c -> i1, i1
  return
}

// CHECK:      %[[C1:.*]] = magic.sym_zxz %{{.*}} ions [0] {x = [2.000000e-01], z = [1.000000e-01]}
// CHECK-NEXT: %[[C2:.*]] = magic.delay %[[C1]]
// CHECK-NEXT: %[[C3:.*]] = magic.recode %[[C2]]
// CHECK-NEXT: %[[C5:.*]] = magic.recode %[[C3]]
// CHECK-NEXT: %[[C6:.*]] = magic.sym_zxz %[[C5]] ions [0, 1] {x = [5.000000e-01, 1.000000e+00], z = [1.300000e+00, 0.000000e+00]}
// CHECK-NEXT: magic.mzd %[[C6]]

// -----

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, [2:1]>
!as = !magic.ion_chain<0, [1:1]>
!bs = !magic.ion_chain<1, [0:1, 2:1]>

// The residual rotation travels with ion 0 to trap 1 and moves through the sym_zxz there.
// CHECK-LABEL: func.func @rz_through_shuttle
func.func @rz_through_shuttle() {
  %a0, %b0 = magic.init : !a, !b
  %a1 = magic.zxz %a0 ions [0] {z1 = [0.1], x = [0.2], z2 = [0.3]} : !a
  %a2, %b1 = magic.shuttle %a1, %b0 : !a, !b -> !as, !bs
  %b2 = magic.sym_zxz %b1 ions [0] {z = [3.0], x = [1.0]} : !bs
  %m0 = magic.mzd %a2 : !as -> i1
  %m1, %m2 = magic.mzd %b2 : !bs -> i1, i1
  return
}

// CHECK:      magic.sym_zxz %{{.*}} ions [0] {x = [2.000000e-01], z = [1.000000e-01]}
// CHECK-NEXT: %{{.*}}, %[[B1:.*]] = magic.shuttle
// CHECK-NEXT: magic.sym_zxz %[[B1]] ions [0] {x = [1.000000e+00], z = [-2.883185307179{{[0-9]*}}]}
// CHECK-NOT:  magic.rz

// -----

!c = !magic.ion_chain<0, [0:1, 1:1]>

// An op the rotations cannot pass gets them as an explicit rz in front of it.
// CHECK-LABEL: func.func @flushed
func.func @flushed() {
  %c0 = magic.init : !c
  %c1 = magic.zxz %c0 ions [0, 1] {z1 = [0.25, 0.5], x = [1.0, 1.0], z2 = [0.25, 0.25]} : !c
  "foreign.use"(%c1) : (!c) -> ()
  return
}

// CHECK:      %[[C1:.*]] = magic.sym_zxz %{{.*}} ions [0, 1] {x = [1.000000e+00, 1.000000e+00], z = [2.500000e-01, 5.000000e-01]}
// CHECK-NEXT: %[[C2:.*]] = magic.rz %[[C1]] ions [0, 1] {angles = [5.000000e-01, 7.500000e-01]}
// CHECK-NEXT: "foreign.use"(%[[C2]])
