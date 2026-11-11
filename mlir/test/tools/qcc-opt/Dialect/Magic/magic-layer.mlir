// RUN: qcc-opt %s --magic-layer --split-input-file | FileCheck %s

!c = !magic.ion_chain<0, [0:1, 1:1]>

// CHECK-LABEL: func.func @one_trap
func.func @one_trap() {
  %c0 = magic.init : !c
  %c1 = magic.zxz %c0 ions [0] {z1 = [0.125], x = [0.25], z2 = [0.375]} : !c
  %c2 = magic.zxz %c1 ions [1] {z1 = [0.5], x = [0.625], z2 = [0.75]} : !c
  %c3 = magic.active_zz %c2 {angles = dense<[[0.0, 0.5], [0.5, 0.0]]> : tensor<2x2xf64>} : !c
  %c4 = magic.rz %c3 ions [0] {angles = [0.5]} : !c
  %c5 = magic.rz %c4 ions [1] {angles = [0.5]} : !c
  %c6 = magic.zxz %c5 ions [1] {z1 = [0.875], x = [1.0], z2 = [1.125]} : !c
  return
}

// CHECK:      %[[C0:.*]] = magic.init : !chain
// First SQ layer, the rz on ion 0 folded back in (z2 = 0.375 + 0.5):
// CHECK-NEXT: %[[C1:.*]] = magic.zxz %[[C0]] ions [0, 1] {x = [2.500000e-01, 6.250000e-01], z1 = [1.250000e-01, 5.000000e-01], z2 = [8.750000e-01, 7.500000e-01]} : !chain
// ZZ layer:
// CHECK-NEXT: %[[C2:.*]] = magic.active_zz %[[C1]] {angles = dense<{{\[\[}}0.000000e+00, 5.000000e-01], [5.000000e-01, 0.000000e+00]]> : tensor<2x2xf64>} : !chain
// Second SQ layer, the rz on ion 1 folded in (z1 = 0.875 + 0.5):
// CHECK-NEXT: magic.zxz %[[C2]] ions [1] {x = [1.000000e+00], z1 = [1.375000e+00], z2 = [1.125000e+00]} : !chain
// CHECK-NEXT: return

// -----

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, [2:1, 3:1]>

// Ion 3 meets no zxz: its two rz float over the ZZ layer and add up to a residual rz.
// CHECK-LABEL: func.func @two_traps
func.func @two_traps() {
  %a0, %b0 = magic.init : !a, !b
  %a1 = magic.zxz %a0 ions [0] {z1 = [0.125], x = [0.25], z2 = [0.375]} : !a
  %b1 = magic.zxz %b0 ions [2] {z1 = [0.5], x = [0.625], z2 = [0.75]} : !b
  %b2 = magic.rz %b1 ions [3] {angles = [0.5]} : !b
  %a2 = magic.active_zz %a1 {angles = dense<[[0.0, 0.5], [0.5, 0.0]]> : tensor<2x2xf64>} : !a
  %a3, %b3 = magic.inter_trap_zz %a2, %b2 ions [1, 2] {angle = 0.25} : !a, !b
  %b4 = magic.active_zz %b3 {angles = dense<[[0.0, 0.125], [0.125, 0.0]]> : tensor<2x2xf64>} : !b
  %b5 = magic.rz %b4 ions [3] {angles = [0.25]} : !b
  %ma0, %ma1 = magic.mzd %a3 : !a -> i1, i1
  %mb0, %mb1 = magic.mzd %b5 : !b -> i1, i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init : !chain, !chain1
// SQ layer:
// CHECK-NEXT: %[[A1:.*]] = magic.zxz %[[INIT]]#0 ions [0] {x = [2.500000e-01], z1 = [1.250000e-01], z2 = [3.750000e-01]} : !chain
// CHECK-NEXT: %[[B1:.*]] = magic.zxz %[[INIT]]#1 ions [2] {x = [6.250000e-01], z1 = [5.000000e-01], z2 = [7.500000e-01]} : !chain1
// All couplings in a single ZZ layer, the one across the traps last:
// CHECK-NEXT: %[[A2:.*]] = magic.active_zz %[[A1]] {angles = dense<{{\[\[}}0.000000e+00, 5.000000e-01], [5.000000e-01, 0.000000e+00]]> : tensor<2x2xf64>} : !chain
// CHECK-NEXT: %[[B2:.*]] = magic.active_zz %[[B1]] {angles = dense<{{\[\[}}0.000000e+00, 1.250000e-01], [1.250000e-01, 0.000000e+00]]> : tensor<2x2xf64>} : !chain1
// CHECK-NEXT: %[[A3:.*]], %[[B3:.*]] = magic.inter_trap_zz %[[A2]], %[[B2]] ions [1, 2] {angle = 2.500000e-01 : f64} : !chain, !chain1
// Residual rz (0.5 + 0.25):
// CHECK-NEXT: %[[B4:.*]] = magic.rz %[[B3]] ions [3] {angles = [7.500000e-01]} : !chain1
// CHECK-NEXT: magic.mzd %[[A3]] : !chain -> i1, i1
// CHECK-NEXT: magic.mzd %[[B4]] : !chain1 -> i1, i1
// CHECK-NEXT: return

// -----

!c = !magic.ion_chain<0, [0:1, 1:1, 2:1]>

// The two zxz on ion 0 fuse into one SQ layer, as the coupling in between does not touch ion 0.
// CHECK-LABEL: func.func @zxz_fuse
func.func @zxz_fuse() {
  %c0 = magic.init : !c
  %c1 = magic.zxz %c0 ions [0] {z1 = [0.125], x = [0.25], z2 = [0.375]} : !c
  %c2 = magic.active_zz %c1 {angles = dense<[[0.0, 0.0, 0.0], [0.0, 0.0, 0.25], [0.0, 0.25, 0.0]]> : tensor<3x3xf64>} : !c
  %c3 = magic.zxz %c2 ions [0] {z1 = [0.5], x = [0.625], z2 = [0.75]} : !c
  return
}

// CHECK:      %[[C0:.*]] = magic.init : !chain
// CHECK-NEXT: %[[C1:.*]] = magic.zxz %[[C0]] ions [0] {
// CHECK-NEXT: magic.active_zz %[[C1]]
// CHECK-NEXT: return

// -----

!c = !magic.ion_chain<0, [0:1, 1:1, 2:1]>

// Each coupling joins the earliest ZZ layer it commutes back to. The couplings of the second active_zz split: some go
// into the first one, others stay and combine with the third one.
// CHECK-LABEL: func.func @earliest_zz_layer
func.func @earliest_zz_layer() {
  %c0 = magic.init : !c
  %c1 = magic.active_zz %c0 {angles = dense<[[0.0, 0.0, 0.0], [0.0, 0.0, 0.25], [0.0, 0.25, 0.0]]> : tensor<3x3xf64>} : !c
  %c2 = magic.zxz %c1 ions [2] {z1 = [0.125], x = [0.25], z2 = [0.375]} : !c
  %c3 = magic.active_zz %c2 {angles = dense<[[0.0, 0.5, 0.0], [0.5, 0.0, 0.375], [0.0, 0.375, 0.0]]> : tensor<3x3xf64>} : !c
  %c4 = magic.active_zz %c3 {angles = dense<[[0.0, 0.25, 0.0], [0.25, 0.0, 0.0], [0.0, 0.0, 0.0]]> : tensor<3x3xf64>} : !c
  %c5 = magic.zxz %c4 ions [0] {z1 = [0.5], x = [0.625], z2 = [0.75]} : !c
  return
}

// Three layers: the zxz on ion 0 joins the one on ion 2.
// CHECK:      %[[C0:.*]] = magic.init : !chain
// CHECK-NEXT: %[[C1:.*]] = magic.active_zz %[[C0]] {angles = dense<{{\[\[}}0.000000e+00, 7.500000e-01, 0.000000e+00], [7.500000e-01, 0.000000e+00, 2.500000e-01], [0.000000e+00, 2.500000e-01, 0.000000e+00]]> : tensor<3x3xf64>} : !chain
// CHECK-NEXT: %[[C2:.*]] = magic.zxz %[[C1]] ions [0, 2] {x = [6.250000e-01, 2.500000e-01], z1 = [5.000000e-01, 1.250000e-01], z2 = [7.500000e-01, 3.750000e-01]} : !chain
// CHECK-NEXT: magic.active_zz %[[C2]] {angles = dense<{{\[\[}}0.000000e+00, 0.000000e+00, 0.000000e+00], [0.000000e+00, 0.000000e+00, 3.750000e-01], [0.000000e+00, 3.750000e-01, 0.000000e+00]]> : tensor<3x3xf64>} : !chain
// CHECK-NEXT: return

// -----

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, [2:1]>

// The couplings cancel out, within the trap and across the traps. They are dropped and do not keep the zxz on ion 1 out
// of the first SQ layer.
// CHECK-LABEL: func.func @couplings_cancel
func.func @couplings_cancel() {
  %a0, %b0 = magic.init : !a, !b
  %a1 = magic.zxz %a0 ions [0] {z1 = [0.125], x = [0.25], z2 = [0.375]} : !a
  %a2 = magic.active_zz %a1 {angles = dense<[[0.0, 0.5], [0.5, 0.0]]> : tensor<2x2xf64>} : !a
  %a3, %b1 = magic.inter_trap_zz %a2, %b0 ions [1, 2] {angle = 0.25} : !a, !b
  %a4 = magic.active_zz %a3 {angles = dense<[[0.0, -0.5], [-0.5, 0.0]]> : tensor<2x2xf64>} : !a
  %a5, %b2 = magic.inter_trap_zz %a4, %b1 ions [1, 2] {angle = -0.25} : !a, !b
  %a6 = magic.zxz %a5 ions [1] {z1 = [0.5], x = [0.625], z2 = [0.75]} : !a
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init : !chain, !chain1
// CHECK-NEXT: magic.zxz %[[INIT]]#0 ions [0, 1] {x = [2.500000e-01, 6.250000e-01], z1 = [1.250000e-01, 5.000000e-01], z2 = [3.750000e-01, 7.500000e-01]} : !chain
// CHECK-NEXT: return

// -----

!a = !magic.ion_chain<0, [0:1]>
!b = !magic.ion_chain<1, [1:1]>

// Trap 0 is measured before the gate on trap 1.
// CHECK-LABEL: func.func @measurements_last
func.func @measurements_last() {
  %a0, %b0 = magic.init : !a, !b
  %m0 = magic.mzd %a0 : !a -> i1
  aux.record_int %m0 : i1
  %b1 = magic.zxz %b0 ions [1] {z1 = [0.0], x = [3.1415926535897931], z2 = [0.0]} : !b
  %m1 = magic.mzd %b1 : !b -> i1
  aux.record_int %m1 : i1
  return
}

// The measurements go behind the layers in their original order; the records come after the measurements.
// CHECK:      %[[INIT:.*]]:2 = magic.init : !chain, !chain1
// CHECK-NEXT: %[[B1:.*]] = magic.zxz %[[INIT]]#1 ions [1]
// CHECK-NEXT: %[[M0:.*]] = magic.mzd %[[INIT]]#0 : !chain -> i1
// CHECK-NEXT: %[[M1:.*]] = magic.mzd %[[B1]] : !chain1 -> i1
// CHECK-NEXT: aux.record_int %[[M0]] : i1
// CHECK-NEXT: aux.record_int %[[M1]] : i1
// CHECK-NEXT: return

// -----

// A function without magic operations is left alone.
// CHECK-LABEL: func.func @untouched
func.func @untouched(%x: i64) -> i64 {
  %c = arith.constant 1 : i64
  %y = arith.addi %x, %c : i64
  return %y : i64
}

// CHECK:      %[[C:.*]] = arith.constant 1 : i64
// CHECK-NEXT: %[[Y:.*]] = arith.addi %arg0, %[[C]] : i64
// CHECK-NEXT: return %[[Y]]

// -----

!c = !magic.ion_chain<0, [0:1, 1:1]>

// A function with an op of a later stage is left alone, so the zxz gates are not fused.
// CHECK-LABEL: func.func @past_layering
func.func @past_layering() {
  %c0 = magic.init : !c
  %c1 = magic.zxz %c0 ions [0] {z1 = [0.5], x = [0.5], z2 = [0.5]} : !c
  %c2 = magic.sym_zxz %c1 ions [1] {z = [0.5], x = [0.25]} : !c
  %c3 = magic.zxz %c2 ions [0] {z1 = [0.5], x = [0.5], z2 = [0.5]} : !c
  return
}

// CHECK:      %[[C0:.*]] = magic.init : !chain
// CHECK-NEXT: %[[C1:.*]] = magic.zxz %[[C0]] ions [0]
// CHECK-NEXT: %[[C2:.*]] = magic.sym_zxz %[[C1]] ions [1]
// CHECK-NEXT: magic.zxz %[[C2]] ions [0]
// CHECK-NEXT: return
