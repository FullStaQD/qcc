// RUN: qcc-opt %s --qcc-attach-device=file=%S/Inputs/device-2x5.mlir --magic-shuttle-inter-trap-zz --split-input-file | FileCheck %s

// Each trap takes five ions. With ions 0, 1 in trap 0 and ions 2, 3, 4 in trap 1 there are three and two free slots:
// either ion of a pair can move over, so the cheaper side decides. In every case the chain types after the lowering
// equal those before.

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, [2:1, 3:1, 4:1]>

// Moving ion 2 (at the front) is cheaper than moving ion 1 (one ion in front of it).
// CHECK-LABEL: func.func @second_side_cheaper
func.func @second_side_cheaper() {
  %a0, %b0 = magic.init : !a, !b
  %a1, %b1 = magic.inter_trap_zz %a0, %b0 ions [1, 2] {angle = 0.5} : !a, !b
  %m0, %m1 = magic.mzd %a1 : !a -> i1, i1
  %m2, %m3, %m4 = magic.mzd %b1 : !b -> i1, i1, i1
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
!b = !magic.ion_chain<1, [2:1, 3:1, 4:1]>

// Moving ion 1 (one ion in front of it) is cheaper than moving ion 4 (two in front).
// CHECK-LABEL: func.func @first_side_cheaper
func.func @first_side_cheaper() {
  %a0, %b0 = magic.init : !a, !b
  %a1, %b1 = magic.inter_trap_zz %a0, %b0 ions [1, 4] {angle = -0.5} : !a, !b
  %m0, %m1 = magic.mzd %a1 : !a -> i1, i1
  %m2, %m3, %m4 = magic.mzd %b1 : !b -> i1, i1, i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init
// CHECK-NEXT: %[[A1:.*]], %[[B1:.*]] = magic.shuttle %[[INIT]]#0, %[[INIT]]#1 : !chain, !chain1 -> !chain2, !chain3
// CHECK-NEXT: %[[A2:.*]], %[[B2:.*]] = magic.shuttle %[[A1]], %[[B1]] : !chain2, !chain3 -> !chain4, !chain5
// CHECK-NEXT: %[[B3:.*]] = magic.active_zz %[[B2]] {angles = dense<{{\[\[}}0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00, -5.000000e-01], [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00], [-5.000000e-01, 0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00]]> : tensor<5x5xf64>} : !chain5
// CHECK-NEXT: %[[B4:.*]], %[[A4:.*]] = magic.shuttle %[[B3]], %[[A2]] : !chain5, !chain4 -> !chain3, !chain2
// CHECK-NEXT: %[[B5:.*]], %[[A5:.*]] = magic.shuttle %[[B4]], %[[A4]] : !chain3, !chain2 -> !chain1, !chain
// CHECK-NEXT: magic.mzd %[[A5]] : !chain
// CHECK-NEXT: magic.mzd %[[B5]] : !chain1
