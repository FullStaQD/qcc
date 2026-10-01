// RUN: qcc-opt %s --qcc-attach-device=file=%S/../Qcc/Inputs/device-2x3.mlir --magic-shuttle-inter-trap-zz --split-input-file | FileCheck %s --check-prefixes=CHECK,CHECK-CAP3
// RUN: qcc-opt %s --qcc-attach-device=file=%S/Inputs/device-2x4.mlir --magic-shuttle-inter-trap-zz --split-input-file | FileCheck %s --check-prefixes=CHECK,CHECK-CAP4

// Both devices hold ions 0, 1 in trap 0 and ions 2, 3 in trap 1. With capacity 3 each trap has one free slot, with
// capacity 4 two. In every case the chain types after the lowering equal those before.

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, [2:1, 3:1]>

// Ion 0 is at the front of trap 0: it alone moves over (one shuttle each way), trap 1 couples it with ion 3.
// CHECK-LABEL: func.func @front
func.func @front() {
  %a0, %b0 = magic.init : !a, !b
  %a1, %b1 = magic.inter_trap_zz %a0, %b0 ions [0, 3] {angle = 0.5} : !a, !b
  %m0, %m1 = magic.mzd %a1 : !a -> i1, i1
  %m2, %m3 = magic.mzd %b1 : !b -> i1, i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init
// CHECK-NEXT: %[[A1:.*]], %[[B1:.*]] = magic.shuttle %[[INIT]]#0, %[[INIT]]#1 : !chain, !chain1 -> !chain2, !chain3
// CHECK-NEXT: %[[B2:.*]] = magic.active_zz %[[B1]] {angles = dense<{{\[\[}}0.000000e+00, 0.000000e+00, 5.000000e-01], [0.000000e+00, 0.000000e+00, 0.000000e+00], [5.000000e-01, 0.000000e+00, 0.000000e+00]]> : tensor<3x3xf64>} : !chain3
// CHECK-NEXT: %[[B3:.*]], %[[A3:.*]] = magic.shuttle %[[B2]], %[[A1]] : !chain3, !chain2 -> !chain1, !chain
// CHECK-NEXT: magic.mzd %[[A3]] : !chain
// CHECK-NEXT: magic.mzd %[[B3]] : !chain1

// -----

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, [2:1, 3:1]>

// Ion 2 is at the front of trap 1, ion 1 behind ion 0: moving ion 2 is cheaper.
// CHECK-LABEL: func.func @cheaper_side
func.func @cheaper_side() {
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

// Both ions behind the front. With two free slots, ions 0 and 1 move over (arriving as [1, 0, 2, 3]) and back. With
// one free slot, ion 1 is swapped to the front, ion 0 carries it over and back, and the swap is undone.
// CHECK-LABEL: func.func @behind_front
func.func @behind_front() {
  %a0, %b0 = magic.init : !a, !b
  %a1, %b1 = magic.inter_trap_zz %a0, %b0 ions [1, 3] {angle = -0.5} : !a, !b
  %m0, %m1 = magic.mzd %a1 : !a -> i1, i1
  %m2, %m3 = magic.mzd %b1 : !b -> i1, i1
  return
}

// CHECK:           %[[INIT:.*]]:2 = magic.init

// CHECK-CAP3-NEXT: %[[A1:.*]] = magic.swap %[[INIT]]#0 ions [0, 1] : !chain
// CHECK-CAP3-NEXT: %[[A2:.*]], %[[B2:.*]] = magic.shuttle %[[A1]], %[[INIT]]#1 : !chain, !chain1 -> !chain2, !chain3
// CHECK-CAP3-NEXT: %[[B3:.*]] = magic.active_zz %[[B2]] {angles = dense<{{\[\[}}0.000000e+00, 0.000000e+00, -5.000000e-01], [0.000000e+00, 0.000000e+00, 0.000000e+00], [-5.000000e-01, 0.000000e+00, 0.000000e+00]]> : tensor<3x3xf64>} : !chain3
// CHECK-CAP3-NEXT: %[[B4:.*]], %[[A4:.*]] = magic.shuttle %[[B3]], %[[A2]] : !chain3, !chain2 -> !chain1, !chain
// CHECK-CAP3-NEXT: %[[A5:.*]] = magic.swap %[[A4]] ions [0, 1] : !chain
// CHECK-CAP3-NEXT: magic.mzd %[[A5]] : !chain
// CHECK-CAP3-NEXT: magic.mzd %[[B4]] : !chain1

// CHECK-CAP4-NEXT: %[[A1:.*]], %[[B1:.*]] = magic.shuttle %[[INIT]]#0, %[[INIT]]#1 : !chain, !chain1 -> !chain2, !chain3
// CHECK-CAP4-NEXT: %[[A2:.*]], %[[B2:.*]] = magic.shuttle %[[A1]], %[[B1]] : !chain2, !chain3 -> !chain4, !chain5
// CHECK-CAP4-NEXT: %[[B3:.*]] = magic.active_zz %[[B2]] {angles = dense<{{\[\[}}0.000000e+00, 0.000000e+00, 0.000000e+00, -5.000000e-01], [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [-5.000000e-01, 0.000000e+00, 0.000000e+00, 0.000000e+00]]> : tensor<4x4xf64>} : !chain5
// CHECK-CAP4-NEXT: %[[B4:.*]], %[[A4:.*]] = magic.shuttle %[[B3]], %[[A2]] : !chain5, !chain4 -> !chain3, !chain2
// CHECK-CAP4-NEXT: %[[B5:.*]], %[[A5:.*]] = magic.shuttle %[[B4]], %[[A4]] : !chain3, !chain2 -> !chain1, !chain
// CHECK-CAP4-NEXT: magic.mzd %[[A5]] : !chain
// CHECK-CAP4-NEXT: magic.mzd %[[B5]] : !chain1
