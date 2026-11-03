// RUN: qcc-opt %s --magic-layer --split-input-file | FileCheck %s

!c = !magic.ion_chain<0, [0:1, 1:1]>

// A Bell pair after decomposition into rzz and zxz: h on both ions; rzz(pi/2); rz(-pi/2) on both; h on ion 1.
// CHECK-LABEL: func.func @bell
func.func @bell() {
  %c0 = magic.init : !c
  %c1 = magic.zxz %c0 ions [0] {z1 = [1.5707963267948966], x = [1.5707963267948966], z2 = [1.5707963267948966]} : !c
  %c2 = magic.zxz %c1 ions [1] {z1 = [1.5707963267948966], x = [1.5707963267948966], z2 = [1.5707963267948966]} : !c
  %c3 = magic.active_zz %c2 {angles = dense<[[0.0, 1.5707963267948966], [1.5707963267948966, 0.0]]> : tensor<2x2xf64>} : !c
  %c4 = magic.rz %c3 ions [0] {angles = [-1.5707963267948966]} : !c
  %c5 = magic.rz %c4 ions [1] {angles = [-1.5707963267948966]} : !c
  %c6 = magic.zxz %c5 ions [1] {z1 = [1.5707963267948966], x = [1.5707963267948966], z2 = [1.5707963267948966]} : !c
  %m0, %m1 = magic.mzd %c6 : !c -> i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  return
}

// One zxz layer over both ions (the trailing rz of ion 0 folded back into it: z2 = 0), one zz block, one zxz layer on
// ion 1 alone (its rz folded in: z1 = 0), then the measurement and the records.
// CHECK:      %[[C0:.*]] = magic.init : !chain
// CHECK-NEXT: %[[C1:.*]] = magic.zxz %[[C0]] ions [0, 1] {x = [1.5707963267948966, 1.5707963267948966], z1 = [1.57079632679489{{[0-9]+}}, 1.5707963267948966], z2 = [0.000000e+00, 1.5707963267948966]} : !chain
// CHECK-NEXT: %[[C2:.*]] = magic.active_zz %[[C1]] {angles = dense<{{\[\[}}0.000000e+00, 1.5707963267948966], [1.5707963267948966, 0.000000e+00]]> : tensor<2x2xf64>} : !chain
// CHECK-NEXT: %[[C3:.*]] = magic.zxz %[[C2]] ions [1] {x = [1.5707963267948966], z1 = [0.000000e+00], z2 = [1.5707963267948966]} : !chain
// CHECK-NEXT: %[[M:.*]]:2 = magic.mzd %[[C3]] : !chain -> i1, i1
// CHECK-NEXT: aux.record_int %[[M]]#0 : i1
// CHECK-NEXT: aux.record_int %[[M]]#1 : i1
// CHECK-NEXT: return

// -----

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, [2:1, 3:1]>

// Two traps. All couplings end up in one block: per trap one active_zz, then the coupling across the traps, with the
// lower trap first. The rz on ion 3 never meets a zxz and stays a residual rz on trap 1.
// CHECK-LABEL: func.func @two_traps
func.func @two_traps() {
  %a0, %b0 = magic.init : !a, !b
  %a1 = magic.zxz %a0 ions [0] {z1 = [0.1], x = [0.2], z2 = [0.3]} : !a
  %b1 = magic.zxz %b0 ions [2] {z1 = [0.4], x = [0.5], z2 = [0.6]} : !b
  %a2 = magic.active_zz %a1 {angles = dense<[[0.0, 0.5], [0.5, 0.0]]> : tensor<2x2xf64>} : !a
  %b2, %a3 = magic.inter_trap_zz %b1, %a2 ions [2, 1] {angle = 0.25} : !b, !a
  %b3 = magic.active_zz %b2 {angles = dense<[[0.0, 0.125], [0.125, 0.0]]> : tensor<2x2xf64>} : !b
  %b4 = magic.rz %b3 ions [3] {angles = [0.75]} : !b
  %ma0, %ma1 = magic.mzd %a3 : !a -> i1, i1
  %mb0, %mb1 = magic.mzd %b4 : !b -> i1, i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init : !chain, !chain1
// CHECK-NEXT: %[[A1:.*]] = magic.zxz %[[INIT]]#0 ions [0] {x = [2.000000e-01], z1 = [1.000000e-01], z2 = [3.000000e-01]} : !chain
// CHECK-NEXT: %[[B1:.*]] = magic.zxz %[[INIT]]#1 ions [2] {x = [5.000000e-01], z1 = [4.000000e-01], z2 = [6.000000e-01]} : !chain1
// CHECK-NEXT: %[[A2:.*]] = magic.active_zz %[[A1]] {angles = dense<{{\[\[}}0.000000e+00, 5.000000e-01], [5.000000e-01, 0.000000e+00]]> : tensor<2x2xf64>} : !chain
// CHECK-NEXT: %[[B2:.*]] = magic.active_zz %[[B1]] {angles = dense<{{\[\[}}0.000000e+00, 1.250000e-01], [1.250000e-01, 0.000000e+00]]> : tensor<2x2xf64>} : !chain1
// CHECK-NEXT: %[[A3:.*]], %[[B3:.*]] = magic.inter_trap_zz %[[A2]], %[[B2]] ions [1, 2] {angle = 2.500000e-01 : f64} : !chain, !chain1
// CHECK-NEXT: %[[B4:.*]] = magic.rz %[[B3]] ions [3] {angles = [7.500000e-01]} : !chain1
// CHECK-NEXT: magic.mzd %[[A3]] : !chain -> i1, i1
// CHECK-NEXT: magic.mzd %[[B4]] : !chain1 -> i1, i1
// CHECK-NEXT: return

// -----

!c = !magic.ion_chain<0, [0:1, 1:1, 2:1]>

// CHECK-LABEL: func.func @merge_across_rz_not_across_x
func.func @merge_across_rz_not_across_x() {
  %c0 = magic.init : !c
  // The first two couplings form one block, the last one a second block.
  %c1 = magic.active_zz %c0 {angles = dense<[[0.0, 0.5, 0.0], [0.5, 0.0, 0.0], [0.0, 0.0, 0.0]]> : tensor<3x3xf64>} : !c
  // Diagonal: does not split the block.
  %c2 = magic.rz %c1 ions [1] {angles = [0.25]} : !c
  %c3 = magic.active_zz %c2 {angles = dense<[[0.0, 0.0, 0.0], [0.0, 0.0, 0.25], [0.0, 0.25, 0.0]]> : tensor<3x3xf64>} : !c
  // x: splits the block.
  %c4 = magic.zxz %c3 ions [1] {z1 = [0.0], x = [3.1415926535897931], z2 = [0.0]} : !c
  %c5 = magic.active_zz %c4 {angles = dense<[[0.0, 0.0, 0.0], [0.0, 0.0, 0.125], [0.0, 0.125, 0.0]]> : tensor<3x3xf64>} : !c
  return
}

// The first block couples (0, 1) and (1, 2), the x on ion 1 sits alone in between and absorbs the rz, the last
// coupling opens a second block.
// CHECK:      %[[C0:.*]] = magic.init : !chain
// CHECK-NEXT: %[[C1:.*]] = magic.active_zz %[[C0]] {angles = dense<{{\[\[}}0.000000e+00, 5.000000e-01, 0.000000e+00], [5.000000e-01, 0.000000e+00, 2.500000e-01], [0.000000e+00, 2.500000e-01, 0.000000e+00]]> : tensor<3x3xf64>} : !chain
// CHECK-NEXT: %[[C2:.*]] = magic.zxz %[[C1]] ions [1] {x = [3.1415926535897931], z1 = [2.500000e-01], z2 = [0.000000e+00]} : !chain
// CHECK-NEXT: magic.active_zz %[[C2]] {angles = dense<{{\[\[}}0.000000e+00, 0.000000e+00, 0.000000e+00], [0.000000e+00, 0.000000e+00, 1.250000e-01], [0.000000e+00, 1.250000e-01, 0.000000e+00]]> : tensor<3x3xf64>} : !chain
// CHECK-NEXT: return

// -----

!c = !magic.ion_chain<0, [0:1, 1:1, 2:1]>

// Two couplings of the same pair in one block add up; ion 2 is not coupled at all.
// CHECK-LABEL: func.func @couplings_add_up
func.func @couplings_add_up() {
  %c0 = magic.init : !c
  %c1 = magic.active_zz %c0 {angles = dense<[[0.0, 0.5, 0.0], [0.5, 0.0, 0.0], [0.0, 0.0, 0.0]]> : tensor<3x3xf64>} : !c
  %c2 = magic.active_zz %c1 {angles = dense<[[0.0, 0.25, 0.0], [0.25, 0.0, 0.0], [0.0, 0.0, 0.0]]> : tensor<3x3xf64>} : !c
  return
}

// CHECK:      %[[C0:.*]] = magic.init : !chain
// CHECK-NEXT: magic.active_zz %[[C0]] {angles = dense<{{\[\[}}0.000000e+00, 7.500000e-01, 0.000000e+00], [7.500000e-01, 0.000000e+00, 0.000000e+00], [0.000000e+00, 0.000000e+00, 0.000000e+00]]> : tensor<3x3xf64>} : !chain
// CHECK-NEXT: return

// -----

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, [2:1]>

// Couplings that cancel out within a block are dropped, within a trap and across traps.
// CHECK-LABEL: func.func @couplings_cancel
func.func @couplings_cancel() {
  %a0, %b0 = magic.init : !a, !b
  %a1 = magic.active_zz %a0 {angles = dense<[[0.0, 0.5], [0.5, 0.0]]> : tensor<2x2xf64>} : !a
  %a2, %b1 = magic.inter_trap_zz %a1, %b0 ions [1, 2] {angle = 0.25} : !a, !b
  %a3 = magic.active_zz %a2 {angles = dense<[[0.0, -0.5], [-0.5, 0.0]]> : tensor<2x2xf64>} : !a
  %a4, %b2 = magic.inter_trap_zz %a3, %b1 ions [1, 2] {angle = -0.25} : !a, !b
  return
}

// CHECK:      magic.init
// CHECK-NEXT: return

// -----

!c = !magic.ion_chain<0, [0:1, 1:1]>

// CHECK-LABEL: func.func @residual_rz
func.func @residual_rz() {
  %c0 = magic.init : !c
  %c1 = magic.rz %c0 ions [0] {angles = [0.5]} : !c
  %c2 = magic.active_zz %c1 {angles = dense<[[0.0, 0.25], [0.25, 0.0]]> : tensor<2x2xf64>} : !c
  %c3 = magic.rz %c2 ions [1] {angles = [0.5]} : !c
  %c4 = magic.rz %c3 ions [1] {angles = [0.5]} : !c
  return
}

// No zxz anywhere, so the rz of both ions end up in one trailing rz (the two of ion 1 added up).
// CHECK:      %[[C0:.*]] = magic.init : !chain
// CHECK-NEXT: %[[C1:.*]] = magic.active_zz %[[C0]]
// CHECK-NEXT: magic.rz %[[C1]] ions [0, 1] {angles = [5.000000e-01, 1.000000e+00]} : !chain
// CHECK-NEXT: return

// -----

!a = !magic.ion_chain<0, [0:1]>
!b = !magic.ion_chain<1, [1:1]>

// Trap 0 is measured before the gate on trap 1. The measurements go behind the layers in their original order; the
// records stay where they are.
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
