// RUN: qcc-opt %s -qc-to-qco -convert-qco-to-qvec -qvec-to-rzz -qvec-to-u-zxz -qvec-fuse-zxz -qvec-layer | FileCheck %s

// End to end through the QVec passes: a 4-qubit QFT (without the final swaps) written in QC with `ctrl { p }`. The
// layered result was also checked numerically against the input's unitary. Expected structure: the Hadamard on q0,
// then alternating: a zz block coupling the current qubit to all later ones, and the next Hadamard (with the cp
// phases folded in), four blocks in total, one qubit fewer each time; then every qubit is measured and recorded.

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

// CHECK-LABEL: func.func @main
// CHECK-DAG:     qco.static 0
// CHECK-DAG:     qco.static 1
// CHECK-DAG:     qco.static 2
// CHECK-DAG:     qco.static 3
// CHECK:         qvec.single u_zxz(%{{.*}}, %{{.*}}, %{{.*}}) %{{.*}} : vector<1x!qco.qubit>, vector<1xf64>
// cp(t) contributes rzz(-t/2): -pi/4, -pi/8, -pi/16 from q0 to q1, q2, q3.
// CHECK:         arith.constant dense<{{\[\[}}0.000000e+00, -0.78539816339744828, -0.39269908169872414, -0.19634954084936207], [-0.78539816339744828, 0.000000e+00, 0.000000e+00, 0.000000e+00], [-0.39269908169872414, 0.000000e+00, 0.000000e+00, 0.000000e+00], [-0.19634954084936207, 0.000000e+00, 0.000000e+00, 0.000000e+00]]> : vector<4x4xf64>
// CHECK:         qvec.global zz(%{{.*}}) %{{.*}} : vector<4x!qco.qubit>, vector<4x4xf64>
// CHECK:         qvec.single u_zxz(%{{.*}}, %{{.*}}, %{{.*}}) %{{.*}} : vector<1x!qco.qubit>, vector<1xf64>
// CHECK:         qvec.global zz(%{{.*}}) %{{.*}} : vector<3x!qco.qubit>, vector<3x3xf64>
// CHECK:         qvec.single u_zxz(%{{.*}}, %{{.*}}, %{{.*}}) %{{.*}} : vector<1x!qco.qubit>, vector<1xf64>
// CHECK:         qvec.global zz(%{{.*}}) %{{.*}} : vector<2x!qco.qubit>, vector<2x2xf64>
// CHECK:         qvec.single u_zxz(%{{.*}}, %{{.*}}, %{{.*}}) %{{.*}} : vector<1x!qco.qubit>, vector<1xf64>
// CHECK-NOT:     qvec.single
// CHECK-NOT:     qvec.global
// CHECK-COUNT-4: qvec.mz %{{.*}} : vector<1x!qco.qubit> -> vector<1xi1>
// CHECK-COUNT-4: aux.record_int
// CHECK:         return
