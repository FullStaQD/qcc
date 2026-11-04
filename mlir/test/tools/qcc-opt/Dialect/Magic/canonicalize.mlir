// RUN: qcc-opt %s --canonicalize --split-input-file | FileCheck %s

!c = !magic.ion_chain<0, [0:1, 1:1, 2:1]>
!c0 = !magic.ion_chain<0, [0:0, 1:1, 2:1]>
!c01 = !magic.ion_chain<0, [0:0, 1:0, 2:1]>

// Two recodes toggling the same ions cancel, a zero delay vanishes: nothing is left between init and mzd.
// CHECK-LABEL: func.func @recode_pair_cancels
func.func @recode_pair_cancels() {
  %c0 = magic.init : !c
  %c1 = magic.recode %c0 : !c -> !c01
  %c2 = magic.delay %c1 {ticks = 0} : !c01
  %c3 = magic.recode %c2 : !c01 -> !c
  %m0, %m1, %m2 = magic.mzd %c3 : !c -> i1, i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init
// CHECK-NEXT: magic.mzd %[[C0]]

// -----

!c = !magic.ion_chain<0, [0:1, 1:1, 2:1]>
!c0 = !magic.ion_chain<0, [0:0, 1:1, 2:1]>
!c01 = !magic.ion_chain<0, [0:0, 1:0, 2:1]>

// Two recodes toggling different ions combine into one.
// CHECK-LABEL: func.func @recode_pair_combines
func.func @recode_pair_combines() {
  %c0 = magic.init : !c
  %c1 = magic.recode %c0 : !c -> !c01
  %c2 = magic.recode %c1 : !c01 -> !c0
  %c3 = magic.delay %c2 {ticks = 5} : !c0
  %m0, %m1, %m2 = magic.mzd %c3 : !c0 -> i1, i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init : !chain
// CHECK-NEXT: %[[C1:.*]] = magic.recode %[[C0]] : !chain -> !chain1
// CHECK-NEXT: %[[C2:.*]] = magic.delay %[[C1]] {ticks = 5 : i64} : !chain1
// CHECK-NEXT: magic.mzd %[[C2]]

// -----

!c = !magic.ion_chain<0, [0:1, 1:1, 2:1]>

// Adjacent rz add up per ion (wrapped into (-pi, pi]); rotations that add up to zero disappear.
// CHECK-LABEL: func.func @rz_merge
func.func @rz_merge() {
  %c0 = magic.init : !c
  %c1 = magic.rz %c0 ions [0, 2] {angles = [0.5, 3.0]} : !c
  %c2 = magic.rz %c1 ions [0, 1, 2] {angles = [-0.5, 0.25, 1.0]} : !c
  %m0, %m1, %m2 = magic.mzd %c2 : !c -> i1, i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init
// CHECK-NEXT: %[[C1:.*]] = magic.rz %[[C0]] ions [1, 2] {angles = [2.500000e-01, -2.283185307179{{[0-9]*}}]}
// CHECK-NEXT: magic.mzd %[[C1]]

// -----

!c = !magic.ion_chain<0, [0:1, 1:1, 2:1]>

// Zero angles are dropped.
// CHECK-LABEL: func.func @rz_zero
func.func @rz_zero() {
  %c0 = magic.init : !c
  %c1 = magic.rz %c0 ions [0, 1] {angles = [0.0, 0.5]} : !c
  %c2 = magic.delay %c1 {ticks = 3} : !c
  %c3 = magic.rz %c2 ions [2] {angles = [0.0]} : !c
  %m0, %m1, %m2 = magic.mzd %c3 : !c -> i1, i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init
// CHECK-NEXT: %[[C1:.*]] = magic.rz %[[C0]] ions [1] {angles = [5.000000e-01]}
// CHECK-NEXT: %[[C2:.*]] = magic.delay %[[C1]]
// CHECK-NEXT: magic.mzd %[[C2]]

// -----

!c = !magic.ion_chain<0, [0:1, 1:1, 2:1]>

// Adjacent rz that add up to zero on every ion disappear.
// CHECK-LABEL: func.func @rz_pair_cancels
func.func @rz_pair_cancels() {
  %c0 = magic.init : !c
  %c1 = magic.rz %c0 ions [0, 2] {angles = [0.5, 3.0]} : !c
  %c2 = magic.rz %c1 ions [0, 2] {angles = [-0.5, -3.0]} : !c
  %m0, %m1, %m2 = magic.mzd %c2 : !c -> i1, i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init
// CHECK-NEXT: magic.mzd %[[C0]]

// -----

!c = !magic.ion_chain<0, [0:1, 1:1, 2:1]>

// Symmetric rotations are native instructions of their own and never merge.
// CHECK-LABEL: func.func @sym_zxz_kept
func.func @sym_zxz_kept() {
  %c0 = magic.init : !c
  %c1 = magic.sym_zxz %c0 ions [0] {z = [0.0], x = [1.0]} : !c
  %c2 = magic.sym_zxz %c1 ions [0] {z = [0.0], x = [1.0]} : !c
  %m0, %m1, %m2 = magic.mzd %c2 : !c -> i1, i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      magic.sym_zxz
// CHECK-NEXT: magic.sym_zxz

// -----

!c = !magic.ion_chain<0, [0:1, 1:1, 2:1]>

// Adjacent active_zz add up entrywise (wrapped into (-pi, pi]).
// CHECK-LABEL: func.func @active_zz_merge
func.func @active_zz_merge() {
  %c0 = magic.init : !c
  %c1 = magic.active_zz %c0 {angles = dense<[[0.0, 0.5, 0.0], [0.5, 0.0, 0.25], [0.0, 0.25, 0.0]]> : tensor<3x3xf64>} : !c
  %c2 = magic.active_zz %c1 {angles = dense<[[0.0, -0.5, 0.125], [-0.5, 0.0, 3.0], [0.125, 3.0, 0.0]]> : tensor<3x3xf64>} : !c
  %m0, %m1, %m2 = magic.mzd %c2 : !c -> i1, i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init
// CHECK-NEXT: %[[C1:.*]] = magic.active_zz %[[C0]] {angles = dense<{{\[\[}}0.000000e+00, 0.000000e+00, 1.250000e-01], [0.000000e+00, 0.000000e+00, -3.033185307179{{[0-9]*}}], [1.250000e-01, -3.033185307179{{[0-9]*}}, 0.000000e+00]]>
// CHECK-NEXT: magic.mzd %[[C1]]

// -----

!c = !magic.ion_chain<0, [0:1, 1:1, 2:1]>

// Adjacent active_zz that add up to zero disappear, and so does one whose angles are all multiples of 2 pi.
// CHECK-LABEL: func.func @active_zz_zero
func.func @active_zz_zero() {
  %c0 = magic.init : !c
  %c1 = magic.active_zz %c0 {angles = dense<[[0.0, 0.5, 0.0], [0.5, 0.0, 0.0], [0.0, 0.0, 0.0]]> : tensor<3x3xf64>} : !c
  %c2 = magic.active_zz %c1 {angles = dense<[[0.0, -0.5, 0.0], [-0.5, 0.0, 0.0], [0.0, 0.0, 0.0]]> : tensor<3x3xf64>} : !c
  %c3 = magic.delay %c2 {ticks = 3} : !c
  %c4 = magic.active_zz %c3 {angles = dense<[[0.0, 6.283185307179586, 0.0], [6.283185307179586, 0.0, -6.283185307179586], [0.0, -6.283185307179586, 0.0]]> : tensor<3x3xf64>} : !c
  %m0, %m1, %m2 = magic.mzd %c4 : !c -> i1, i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init
// CHECK-NEXT: %[[C1:.*]] = magic.delay %[[C0]]
// CHECK-NEXT: magic.mzd %[[C1]]

// -----

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, [2:1]>

// Adjacent inter_trap_zz on the same ions add up; on different ions, or with an rz on one of the chains in between,
// they stay apart.
// CHECK-LABEL: func.func @inter_trap_zz_merge
func.func @inter_trap_zz_merge() {
  %a0, %b0 = magic.init : !a, !b
  %a1, %b1 = magic.inter_trap_zz %a0, %b0 ions [0, 2] {angle = 0.5} : !a, !b
  %a2, %b2 = magic.inter_trap_zz %a1, %b1 ions [0, 2] {angle = 0.25} : !a, !b
  %a3, %b3 = magic.inter_trap_zz %a2, %b2 ions [1, 2] {angle = 0.125} : !a, !b
  %b4 = magic.rz %b3 ions [2] {angles = [0.25]} : !b
  %a5, %b5 = magic.inter_trap_zz %a3, %b4 ions [1, 2] {angle = 0.125} : !a, !b
  %m0, %m1 = magic.mzd %a5 : !a -> i1, i1
  %m2 = magic.mzd %b5 : !b -> i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init
// CHECK-NEXT: %[[A1:.*]], %[[B1:.*]] = magic.inter_trap_zz %[[INIT]]#0, %[[INIT]]#1 ions [0, 2] {angle = 7.500000e-01 : f64}
// CHECK-NEXT: %[[A2:.*]], %[[B2:.*]] = magic.inter_trap_zz %[[A1]], %[[B1]] ions [1, 2] {angle = 1.250000e-01 : f64}
// CHECK-NEXT: %[[B3:.*]] = magic.rz %[[B2]] ions [2]
// CHECK-NEXT: %[[A4:.*]], %[[B4:.*]] = magic.inter_trap_zz %[[A2]], %[[B3]] ions [1, 2] {angle = 1.250000e-01 : f64}
// CHECK-NEXT: magic.mzd %[[A4]]
// CHECK-NEXT: magic.mzd %[[B4]]

// -----

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, [2:1]>

// Adjacent inter_trap_zz that add up to zero disappear, and so do those whose angle is a multiple of 2 pi.
// CHECK-LABEL: func.func @inter_trap_zz_zero
func.func @inter_trap_zz_zero() {
  %a0, %b0 = magic.init : !a, !b
  %a1, %b1 = magic.inter_trap_zz %a0, %b0 ions [0, 2] {angle = 0.5} : !a, !b
  %a2, %b2 = magic.inter_trap_zz %a1, %b1 ions [0, 2] {angle = -0.5} : !a, !b
  %a3, %b3 = magic.inter_trap_zz %a2, %b2 ions [1, 2] {angle = 0.0} : !a, !b
  %a4, %b4 = magic.inter_trap_zz %a3, %b3 ions [0, 2] {angle = -6.283185307179586} : !a, !b
  %m0, %m1 = magic.mzd %a4 : !a -> i1, i1
  %m2 = magic.mzd %b4 : !b -> i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      %[[INIT:.*]]:2 = magic.init
// CHECK-NEXT: magic.mzd %[[INIT]]#0
// CHECK-NEXT: magic.mzd %[[INIT]]#1

// -----

!t0 = !magic.ion_chain<0, [0:1]>
!t1 = !magic.ion_chain<1, [1:1]>

// A trap whose chain is unused is not loaded: the init shrinks to the traps in use, their ion ids stay.
// CHECK:       !chain = !magic.ion_chain<1, [1:1]>
// CHECK-LABEL: func.func @unused_trap
func.func @unused_trap() {
  %a0, %b0, %c0 = magic.init : !t0, !t1, !magic.ion_chain<2, []>
  %m1 = magic.mzd %b0 : !t1 -> i1
  aux.record_int %m1 : i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init : !chain{{$}}
// CHECK-NEXT: magic.mzd %[[C0]]
