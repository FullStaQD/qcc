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
  %c2 = magic.rz %c1 ions [1, 0, 2] {angles = [0.25, -0.5, 1.0]} : !c
  %m0, %m1, %m2 = magic.mzd %c2 : !c -> i1, i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init
// CHECK-NEXT: %[[C1:.*]] = magic.rz %[[C0]] ions [2, 1] {angles = [-2.283185307179{{[0-9]*}}, 2.500000e-01]}
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
