// RUN: qcc-opt %s --qcc-attach-device=file=%S/Inputs/device-2x5.mlir -convert-qc-to-qref -convert-qref-to-qcirc \
// RUN:   -qcirc-to-rzz -qcirc-to-u-zxz -qcirc-fuse-zxz -convert-qcirc-to-magic -magic-layer | FileCheck %s

// End to end from QC through the layering: a 4-qubit QFT (without the final swaps) on one trap. Expected structure:
// the Hadamard on q0, then alternating: a ZZ layer coupling the current qubit to all later ones, and the next Hadamard
// (with the cp phases folded in).
// CHECK-LABEL: func.func @main
func.func @main() attributes { qcc.entry_point } {
  %pi2 = arith.constant 1.5707963267948966 : f64
  %pi4 = arith.constant 0.7853981633974483 : f64
  %pi8 = arith.constant 0.39269908169872414 : f64
  %q0 = qc.static 0 : !qc.qubit
  %q1 = qc.static 1 : !qc.qubit
  %q2 = qc.static 2 : !qc.qubit
  %q3 = qc.static 3 : !qc.qubit
  qc.h %q0 : !qc.qubit
  qc.ctrl(%q1) targets(%t = %q0) { qc.p(%pi2) %t : !qc.qubit  qc.yield } : {!qc.qubit}, {!qc.qubit}
  qc.ctrl(%q2) targets(%t = %q0) { qc.p(%pi4) %t : !qc.qubit  qc.yield } : {!qc.qubit}, {!qc.qubit}
  qc.ctrl(%q3) targets(%t = %q0) { qc.p(%pi8) %t : !qc.qubit  qc.yield } : {!qc.qubit}, {!qc.qubit}
  qc.h %q1 : !qc.qubit
  qc.ctrl(%q2) targets(%t = %q1) { qc.p(%pi2) %t : !qc.qubit  qc.yield } : {!qc.qubit}, {!qc.qubit}
  qc.ctrl(%q3) targets(%t = %q1) { qc.p(%pi4) %t : !qc.qubit  qc.yield } : {!qc.qubit}, {!qc.qubit}
  qc.h %q2 : !qc.qubit
  qc.ctrl(%q3) targets(%t = %q2) { qc.p(%pi2) %t : !qc.qubit  qc.yield } : {!qc.qubit}, {!qc.qubit}
  qc.h %q3 : !qc.qubit
  %m0 = qc.measure %q0 : !qc.qubit -> i1
  %m1 = qc.measure %q1 : !qc.qubit -> i1
  %m2 = qc.measure %q2 : !qc.qubit -> i1
  %m3 = qc.measure %q3 : !qc.qubit -> i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  aux.record_int %m3 : i1
  return
}

// CHECK:         magic.init : !chain, !chain1
// CHECK-NEXT:    magic.zxz %{{.*}} ions [0]
// cp(t) contributes rzz(-t/2): -pi/4, -pi/8, -pi/16 from q0 to q1, q2, q3.
// CHECK-NEXT:    magic.active_zz %{{.*}} {angles = dense<{{\[\[}}0.000000e+00, -0.78539816339744828, -0.39269908169872414, -0.19634954084936207], [-0.78539816339744828, 0.000000e+00, 0.000000e+00, 0.000000e+00], [-0.39269908169872414, 0.000000e+00, 0.000000e+00, 0.000000e+00], [-0.19634954084936207, 0.000000e+00, 0.000000e+00, 0.000000e+00]]> : tensor<4x4xf64>}
// CHECK-NEXT:    magic.zxz %{{.*}} ions [1]
// CHECK-NEXT:    magic.active_zz
// CHECK-NEXT:    magic.zxz %{{.*}} ions [2]
// CHECK-NEXT:    magic.active_zz
// CHECK-NEXT:    magic.zxz %{{.*}} ions [3]
// CHECK-NEXT:    magic.mzd %{{.*}} : !chain -> i1, i1, i1, i1
// CHECK-COUNT-4: aux.record_int
// CHECK-NEXT:    return
