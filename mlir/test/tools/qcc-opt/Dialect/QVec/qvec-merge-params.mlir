// RUN: qcc-opt %s -qvec-merge | FileCheck %s

// Parametrised gates are not merged (yet, see the pass description); the parameter-free gates next to them still are.

// CHECK-LABEL: func.func @parametrised_ops_pass_through
func.func @parametrised_ops_pass_through() {
    %q0, %q1, %q2, %q3 = qcc.static [0, 1, 2, 3] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qcc.qubit>
    %v2 = vector.from_elements %q2 : vector<1x!qcc.qubit>
    %v3 = vector.from_elements %q3 : vector<1x!qcc.qubit>
    %theta = arith.constant dense<0.5> : vector<1xf64>

    %h0 = qvec.single h %v0 : vector<1x!qcc.qubit>
    %h1 = qvec.single h %v1 : vector<1x!qcc.qubit>

    %r0 = qvec.single rz(%theta) %h0 : vector<1xf64>, vector<1x!qcc.qubit>
    %r1 = qvec.single rz(%theta) %h1 : vector<1xf64>, vector<1x!qcc.qubit>

    %a0, %b0 = qvec.pair rzz(%theta) %r0, %v2 : vector<1xf64>, vector<1x!qcc.qubit>
    %a1, %b1 = qvec.pair rzz(%theta) %r1, %v3 : vector<1xf64>, vector<1x!qcc.qubit>

    func.return
}

// CHECK:         qvec.single h %{{.*}} : vector<2x!qcc.qubit>
// CHECK-NOT:     qvec.single h
// CHECK:         qvec.single rz(%{{.*}}) %{{.*}} : vector<1xf64>, vector<1x!qcc.qubit>
// CHECK:         qvec.single rz(%{{.*}}) %{{.*}} : vector<1xf64>, vector<1x!qcc.qubit>
// CHECK:         qvec.pair rzz(%{{.*}}) %{{.*}}, %{{.*}} : vector<1xf64>, vector<1x!qcc.qubit>
// CHECK:         qvec.pair rzz(%{{.*}}) %{{.*}}, %{{.*}} : vector<1xf64>, vector<1x!qcc.qubit>
