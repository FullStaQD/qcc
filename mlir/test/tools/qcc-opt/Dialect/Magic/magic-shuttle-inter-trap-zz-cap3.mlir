// RUN: qcc-opt %s --qcc-attach-device=file=%S/Inputs/device-2x3.mlir --magic-shuttle-inter-trap-zz --split-input-file | FileCheck %s

// Each trap takes three ions. With two ions per trap there is one free slot each: only a front ion can move over. In
// every case the chain types after the lowering equal those before.

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, [2:1, 3:1]>

// Shuttling only possible with ion 2 due to capacity constraints.
// CHECK-LABEL: func.func @second_ion_at_front
func.func @second_ion_at_front() {
  %a0, %b0 = magic.init : !a, !b
  %a1, %b1 = magic.inter_trap_zz %a0, %b0 ions [1, 2] {angle = 0.5} : !a, !b
  %m0, %m1 = magic.mzd %a1 : !a -> i1, i1
  %m2, %m3 = magic.mzd %b1 : !b -> i1, i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init
// CHECK-NEXT: %[[B1:.*]], %[[A1:.*]] = magic.shuttle %[[INIT]]#1, %[[INIT]]#0
// CHECK-NEXT: %[[A2:.*]] = magic.active_zz %[[A1]] {angles = dense<{{\[\[}}0.000000e+00, 0.000000e+00, 5.000000e-01], [0.000000e+00, 0.000000e+00, 0.000000e+00], [5.000000e-01, 0.000000e+00, 0.000000e+00]]> : tensor<3x3xf64>}
// CHECK-NEXT: %[[A3:.*]], %[[B3:.*]] = magic.shuttle %[[A2]], %[[B1]]
// CHECK-NEXT: magic.mzd %[[A3]] : !chain
// CHECK-NEXT: magic.mzd %[[B3]] : !chain1

// -----

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, [2:1, 3:1]>

// Due to capacity constraints we have to use swaps to bring the quantum info of one of the two ions to the front.
// CHECK-LABEL: func.func @swap_to_front
func.func @swap_to_front() {
  %a0, %b0 = magic.init : !a, !b
  %a1, %b1 = magic.inter_trap_zz %a0, %b0 ions [1, 3] {angle = -0.5} : !a, !b
  %m0, %m1 = magic.mzd %a1 : !a -> i1, i1
  %m2, %m3 = magic.mzd %b1 : !b -> i1, i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init
// CHECK-NEXT: %[[A1:.*]] = magic.swap %[[INIT]]#0 ions [0, 1] : !chain
// CHECK-NEXT: %[[A2:.*]], %[[B2:.*]] = magic.shuttle %[[A1]], %[[INIT]]#1 : !chain, !chain1 -> !chain2, !chain3
// CHECK-NEXT: %[[B3:.*]] = magic.active_zz %[[B2]] {angles = dense<{{\[\[}}0.000000e+00, 0.000000e+00, -5.000000e-01], [0.000000e+00, 0.000000e+00, 0.000000e+00], [-5.000000e-01, 0.000000e+00, 0.000000e+00]]> : tensor<3x3xf64>} : !chain3
// CHECK-NEXT: %[[B4:.*]], %[[A4:.*]] = magic.shuttle %[[B3]], %[[A2]] : !chain3, !chain2 -> !chain1, !chain
// CHECK-NEXT: %[[A5:.*]] = magic.swap %[[A4]] ions [0, 1] : !chain
// CHECK-NEXT: magic.mzd %[[A5]] : !chain
// CHECK-NEXT: magic.mzd %[[B4]] : !chain1

// -----

!a = !magic.ion_chain<0, [0:1]>
!b = !magic.ion_chain<1, [1:1, 2:1, 3:1]>

// Trap 1 is full, so nothing can move there: the swap happens in trap 1 and its front ion goes to trap 0.
// CHECK-LABEL: func.func @swap_in_other_trap
func.func @swap_in_other_trap() {
  %a0, %b0 = magic.init : !a, !b
  %a1, %b1 = magic.inter_trap_zz %a0, %b0 ions [0, 3] {angle = -0.5} : !a, !b
  %m0 = magic.mzd %a1 : !a -> i1
  %m1, %m2, %m3 = magic.mzd %b1 : !b -> i1, i1, i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init
// CHECK-NEXT: %[[B1:.*]] = magic.swap %[[INIT]]#1 ions [1, 3] : !chain1
// CHECK-NEXT: %[[B2:.*]], %[[A2:.*]] = magic.shuttle %[[B1]], %[[INIT]]#0 : !chain1, !chain -> !chain2, !chain3
// CHECK-NEXT: %[[A3:.*]] = magic.active_zz %[[A2]] {angles = dense<{{\[\[}}0.000000e+00, -5.000000e-01], [-5.000000e-01, 0.000000e+00]]> : tensor<2x2xf64>} : !chain3
// CHECK-NEXT: %[[A4:.*]], %[[B4:.*]] = magic.shuttle %[[A3]], %[[B2]] : !chain3, !chain2 -> !chain, !chain1
// CHECK-NEXT: %[[B5:.*]] = magic.swap %[[B4]] ions [1, 3] : !chain1
// CHECK-NEXT: magic.mzd %[[A4]] : !chain
// CHECK-NEXT: magic.mzd %[[B5]] : !chain1

// -----

!a  = !magic.ion_chain<0, [0:1, 1:1]>
!b  = !magic.ion_chain<1, [2:1, 3:1]>
!ai = !magic.ion_chain<0, [0:0, 1:1]>
!bi = !magic.ion_chain<1, [2:1, 3:0]>

// The coupling needs active ions: ion 3 and the front ion 0, which carries ion 1 over, are recoded around the
// shuttles.
// CHECK:       !chain = !magic.ion_chain<0, [0:1, 1:1]>
// CHECK:       !chain1 = !magic.ion_chain<1, [2:1, 3:1]>
// CHECK:       !chain2 = !magic.ion_chain<0, [0:0, 1:1]>
// CHECK:       !chain3 = !magic.ion_chain<1, [2:1, 3:0]>
// CHECK-LABEL: func.func @inactive_ions
func.func @inactive_ions() {
  %a0, %b0 = magic.init : !a, !b
  %a1 = magic.recode %a0 : !a -> !ai
  %b1 = magic.recode %b0 : !b -> !bi
  %a2, %b2 = magic.inter_trap_zz %a1, %b1 ions [1, 3] {angle = -0.5} : !ai, !bi
  %m0, %m1 = magic.mzd %a2 : !ai -> i1, i1
  %m2, %m3 = magic.mzd %b2 : !bi -> i1, i1
  return
}

// CHECK:      %[[A1:.*]] = magic.recode %{{.*}} : !chain -> !chain2
// CHECK-NEXT: %[[B1:.*]] = magic.recode %{{.*}} : !chain1 -> !chain3
// CHECK-NEXT: %[[A2:.*]] = magic.swap %[[A1]] ions [0, 1] : !chain2
// CHECK-NEXT: %[[A3:.*]] = magic.recode %[[A2]] : !chain2 -> !chain
// CHECK-NEXT: %[[B3:.*]] = magic.recode %[[B1]] : !chain3 -> !chain1
// CHECK-NEXT: %[[A4:.*]], %[[B4:.*]] = magic.shuttle %[[A3]], %[[B3]]
// CHECK-NEXT: %[[B5:.*]] = magic.active_zz %[[B4]] {angles = dense<{{\[\[}}0.000000e+00, 0.000000e+00, -5.000000e-01], [0.000000e+00, 0.000000e+00, 0.000000e+00], [-5.000000e-01, 0.000000e+00, 0.000000e+00]]> : tensor<3x3xf64>}
// CHECK-NEXT: %[[B6:.*]], %[[A6:.*]] = magic.shuttle %[[B5]], %[[A4]]
// CHECK-NEXT: %[[B7:.*]] = magic.recode %[[B6]] : !chain1 -> !chain3
// CHECK-NEXT: %[[A7:.*]] = magic.recode %[[A6]] : !chain -> !chain2
// CHECK-NEXT: %[[A8:.*]] = magic.swap %[[A7]] ions [0, 1] : !chain2
// CHECK-NEXT: magic.mzd %[[A8]] : !chain2
// CHECK-NEXT: magic.mzd %[[B7]] : !chain3
