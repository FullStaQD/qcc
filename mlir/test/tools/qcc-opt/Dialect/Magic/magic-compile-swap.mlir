// RUN: qcc-opt %s --magic-compile-swap | FileCheck %s

// swap(1, 2) = cx(1, 2) cx(2, 1) cx(1, 2), each cx(c, t) = h(t) cz h(t) with cz = rzz(pi/2) rz(-pi/2) rz(-pi/2) and
// h = zxz(pi/2, pi/2, pi/2), all up to a global phase. Ion 0 is not involved.
// CHECK-LABEL: func.func @swap
func.func @swap() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1, 2:1]>
  %c1 = magic.swap %c0 ions [1, 2] : !magic.ion_chain<0, [0:1, 1:1, 2:1]>
  %m0, %m1, %m2 = magic.mzd %c1 : !magic.ion_chain<0, [0:1, 1:1, 2:1]> -> i1, i1, i1
  return
}

// CHECK:      %[[C0:.*]] = magic.init
// CHECK-NEXT: %[[C1:.*]] = magic.zxz %[[C0]] ions [2] {x = [1.5707963267948966], z1 = [1.5707963267948966], z2 = [1.5707963267948966]}
// CHECK-NEXT: %[[C2:.*]] = magic.active_zz %[[C1]] {angles = dense<{{\[\[}}0.000000e+00, 0.000000e+00, 0.000000e+00], [0.000000e+00, 0.000000e+00, 1.5707963267948966], [0.000000e+00, 1.5707963267948966, 0.000000e+00]]> : tensor<3x3xf64>}
// CHECK-NEXT: %[[C3:.*]] = magic.rz %[[C2]] ions [1, 2] {angles = [-1.5707963267948966, -1.5707963267948966]}
// CHECK-NEXT: %[[C4:.*]] = magic.zxz %[[C3]] ions [2]
// CHECK-NEXT: %[[C5:.*]] = magic.zxz %[[C4]] ions [1]
// CHECK-NEXT: %[[C6:.*]] = magic.active_zz %[[C5]]
// CHECK-NEXT: %[[C7:.*]] = magic.rz %[[C6]] ions [1, 2]
// CHECK-NEXT: %[[C8:.*]] = magic.zxz %[[C7]] ions [1]
// CHECK-NEXT: %[[C9:.*]] = magic.zxz %[[C8]] ions [2]
// CHECK-NEXT: %[[C10:.*]] = magic.active_zz %[[C9]]
// CHECK-NEXT: %[[C11:.*]] = magic.rz %[[C10]] ions [1, 2]
// CHECK-NEXT: %[[C12:.*]] = magic.zxz %[[C11]] ions [2]
// CHECK-NEXT: magic.mzd %[[C12]]
