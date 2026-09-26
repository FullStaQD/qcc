// RUN: qcc-opt %s -qvec-merge | FileCheck %s

// Parametrised gates and global gates are not merged (yet, see the pass description); the parameter-free gates next
// to them still are.

// CHECK-LABEL: func.func @parametrised_ops_pass_through
func.func @parametrised_ops_pass_through() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %q2 = qco.static 2 : !qco.qubit
    %q3 = qco.static 3 : !qco.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qco.qubit>
    %v2 = vector.from_elements %q2 : vector<1x!qco.qubit>
    %v3 = vector.from_elements %q3 : vector<1x!qco.qubit>
    %theta = arith.constant dense<0.5> : vector<1xf64>
    %angles = arith.constant dense<[[0.0, 0.5], [0.5, 0.0]]> : vector<2x2xf64>

    %h0 = qvec.single h %v0 : vector<1x!qco.qubit>
    %h1 = qvec.single h %v1 : vector<1x!qco.qubit>

    %r0 = qvec.single rz(%theta) %h0 : vector<1x!qco.qubit>, vector<1xf64>
    %r1 = qvec.single rz(%theta) %h1 : vector<1x!qco.qubit>, vector<1xf64>

    %a0, %b0 = qvec.pair rzz(%theta) %r0, %v2 : vector<1x!qco.qubit>, vector<1xf64>
    %a1, %b1 = qvec.pair rzz(%theta) %r1, %v3 : vector<1x!qco.qubit>, vector<1xf64>

    %e0 = vector.extract %a0[0] : !qco.qubit from vector<1x!qco.qubit>
    %e1 = vector.extract %b0[0] : !qco.qubit from vector<1x!qco.qubit>
    %w = vector.from_elements %e0, %e1 : vector<2x!qco.qubit>
    %z = qvec.global zz(%angles) %w : vector<2x!qco.qubit>, vector<2x2xf64>

    func.return
}

// CHECK:         qvec.single h %{{.*}} : vector<2x!qco.qubit>
// CHECK-NOT:     qvec.single h
// CHECK:         qvec.single rz(%{{.*}}) %{{.*}} : vector<1x!qco.qubit>, vector<1xf64>
// CHECK:         qvec.single rz(%{{.*}}) %{{.*}} : vector<1x!qco.qubit>, vector<1xf64>
// CHECK:         qvec.pair rzz(%{{.*}}) %{{.*}}, %{{.*}} : vector<1x!qco.qubit>, vector<1xf64>
// CHECK:         qvec.pair rzz(%{{.*}}) %{{.*}}, %{{.*}} : vector<1x!qco.qubit>, vector<1xf64>
// CHECK:         qvec.global zz(%{{.*}}) %{{.*}} : vector<2x!qco.qubit>, vector<2x2xf64>
