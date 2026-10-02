// RUN: qcc-opt %s --qcc-attach-device=file=%S/../Qcc/Inputs/device-2x3.mlir --magic-compile-active-zz-trivially --split-input-file | FileCheck %s

// The device: time unit 1 us; J = 1.0 rad/s for two ions; for three ions 1.0 between neighbours, 0.5 for the outer
// pair. The tick counts pin the assumed delay convention t = |angle| / |J|: a change of it shows up here.

// Two active ions, rzz(pi/2): t = pi/2 s = 1570796 us. No other ion to switch off.
// CHECK-LABEL: func.func @pair
func.func @pair() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
  %c1 = magic.active_zz %c0 {angles = dense<[[0.0, 1.5707963267948966],
                                             [1.5707963267948966, 0.0]]> : tensor<2x2xf64>} : !magic.ion_chain<0, [0:1, 1:1]>
  %m0, %m1 = magic.mzd %c1 : !magic.ion_chain<0, [0:1, 1:1]> -> i1, i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init
// CHECK-NEXT: %[[C1:.*]] = magic.delay %[[C0]] {ticks = 1570796 : i64} : !chain
// CHECK-NEXT: magic.mzd %[[C1]]

// -----

// Three active ions, two couplings with different strengths. X flip to account for the sign.
// CHECK-LABEL: func.func @three_ions
func.func @three_ions() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1, 2:1]>
  %c1 = magic.active_zz %c0 {angles = dense<[[0.0, 1.5707963267948966, -1.5707963267948966],
                                             [1.5707963267948966, 0.0, 0.0],
                                             [-1.5707963267948966, 0.0, 0.0]]> : tensor<3x3xf64>} : !magic.ion_chain<0, [0:1, 1:1, 2:1]>
  %m0, %m1, %m2 = magic.mzd %c1 : !magic.ion_chain<0, [0:1, 1:1, 2:1]> -> i1, i1, i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init : !chain
// CHECK-NEXT: %[[C1:.*]] = magic.recode %[[C0]] : !chain -> !chain1
// CHECK-NEXT: %[[C2:.*]] = magic.delay %[[C1]] {ticks = 1570796 : i64} : !chain1
// CHECK-NEXT: %[[C3:.*]] = magic.recode %[[C2]] : !chain1 -> !chain
// CHECK-NEXT: %[[C4:.*]] = magic.recode %[[C3]] : !chain -> !chain2
// CHECK-NEXT: %[[C5:.*]] = magic.sym_zxz %[[C4]] ions [0] {x = [3.1415926535897931], z = [0.000000e+00]} : !chain2
// CHECK-NEXT: %[[C6:.*]] = magic.delay %[[C5]] {ticks = 3141593 : i64} : !chain2
// CHECK-NEXT: %[[C7:.*]] = magic.sym_zxz %[[C6]] ions [0] {x = [3.1415926535897931], z = [0.000000e+00]} : !chain2
// CHECK-NEXT: %[[C8:.*]] = magic.recode %[[C7]] : !chain2 -> !chain
// CHECK-NEXT: magic.mzd %[[C8]]

// -----

// An inactive ion counts for the choice of J (three ions present) but is not coupled.
// CHECK-LABEL: func.func @inactive_ion
func.func @inactive_ion() {
  %c = magic.init : !magic.ion_chain<0, [0:1, 1:1, 2:1]>
  %c0 = magic.recode %c : !magic.ion_chain<0, [0:1, 1:1, 2:1]> -> !magic.ion_chain<0, [0:1, 1:0, 2:1]>
  %c1 = magic.active_zz %c0 {angles = dense<[[0.0, 1.5707963267948966],
                                             [1.5707963267948966, 0.0]]> : tensor<2x2xf64>} : !magic.ion_chain<0, [0:1, 1:0, 2:1]>
  %m0, %m1, %m2 = magic.mzd %c1 : !magic.ion_chain<0, [0:1, 1:0, 2:1]> -> i1, i1, i1
  return
}

// CHECK:      %[[C0:.*]] = magic.recode
// CHECK-NEXT: %[[C1:.*]] = magic.delay %[[C0]] {ticks = 3141593 : i64} : !chain1
// CHECK-NEXT: magic.mzd %[[C1]]

// -----

// Nothing to couple: the op is erased.
// CHECK-LABEL: func.func @zero
func.func @zero() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
  %c1 = magic.active_zz %c0 {angles = dense<0.0> : tensor<2x2xf64>} : !magic.ion_chain<0, [0:1, 1:1]>
  %m0, %m1 = magic.mzd %c1 : !magic.ion_chain<0, [0:1, 1:1]> -> i1, i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init
// CHECK-NEXT: magic.mzd %[[C0]]
