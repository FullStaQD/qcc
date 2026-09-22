// RUN: qcc-opt %s | FileCheck %s

// CHECK-LABEL: @single_gates
func.func @single_gates(%qs: vector<2x!qco.qubit>) {
    // CHECK: %[[H:.*]] = qvec.single h %{{.*}} : vector<2x!qco.qubit>
    %h = qvec.single h %qs : vector<2x!qco.qubit>
    // CHECK: %[[X:.*]] = qvec.single x %[[H]]
    %x = qvec.single x %h : vector<2x!qco.qubit>
    // CHECK: %[[S:.*]] = qvec.single s %[[X]]
    %s = qvec.single s %x : vector<2x!qco.qubit>
    // CHECK: qvec.single sdg %[[S]]
    %sdg = qvec.single sdg %s : vector<2x!qco.qubit>
    // ... there are more but lets stop here.

    func.return
}

// CHECK-LABEL: @parametrised_single_gates
func.func @parametrised_single_gates(%qs: vector<2x!qco.qubit>, %theta: vector<2xf64>) {
    // CHECK: %[[RX:.*]] = qvec.single rx(%{{.*}}) %{{.*}} : vector<2x!qco.qubit>, vector<2xf64>
    %rx = qvec.single rx(%theta) %qs : vector<2x!qco.qubit>, vector<2xf64>
    // CHECK: %[[RY:.*]] = qvec.single ry(%{{.*}}) %[[RX]] : vector<2x!qco.qubit>, vector<2xf64>
    %ry = qvec.single ry(%theta) %rx : vector<2x!qco.qubit>, vector<2xf64>
    // CHECK: %[[RZ:.*]] = qvec.single rz(%{{.*}}) %[[RY]] : vector<2x!qco.qubit>, vector<2xf64>
    %rz = qvec.single rz(%theta) %ry : vector<2x!qco.qubit>, vector<2xf64>
    // Three parameters share one type.
    // CHECK: qvec.single u_zxz(%{{.*}}, %{{.*}}, %{{.*}}) %[[RZ]] : vector<2x!qco.qubit>, vector<2xf64>
    %u = qvec.single u_zxz(%theta, %theta, %theta) %rz : vector<2x!qco.qubit>, vector<2xf64>

    func.return
}

// CHECK-LABEL: @pair_gates
func.func @pair_gates(%as: vector<2x!qco.qubit>, %bs: vector<2x!qco.qubit>, %theta: vector<2xf64>) {
    // CHECK: %[[CA:.*]], %[[CB:.*]] = qvec.pair cx %{{.*}}, %{{.*}} : vector<2x!qco.qubit>
    %ca, %cb = qvec.pair cx %as, %bs : vector<2x!qco.qubit>
    // CHECK: %[[IA:.*]], %[[IB:.*]] = qvec.pair iswap %[[CA]], %[[CB]]
    %ia, %ib = qvec.pair iswap %ca, %cb : vector<2x!qco.qubit>
    // CHECK: %[[RA:.*]], %[[RB:.*]] = qvec.pair rzz(%{{.*}}) %[[IA]], %[[IB]] : vector<2x!qco.qubit>, vector<2xf64>
    %ra, %rb = qvec.pair rzz(%theta) %ia, %ib : vector<2x!qco.qubit>, vector<2xf64>
    // CHECK: qvec.pair cp(%{{.*}}) %[[RA]], %[[RB]] : vector<2x!qco.qubit>, vector<2xf64>
    %pa, %pb = qvec.pair cp(%theta) %ra, %rb : vector<2x!qco.qubit>, vector<2xf64>
    // ... there are more but lets stop here.

    func.return
}

// CHECK-LABEL: @global_gates
func.func @global_gates(%qs: vector<2x!qco.qubit>, %angles: vector<2x2xf64>) {
    // CHECK: %[[Z:.*]] = qvec.global zz(%{{.*}}) %{{.*}} : vector<2x!qco.qubit>, vector<2x2xf64>
    %z = qvec.global zz(%angles) %qs : vector<2x!qco.qubit>, vector<2x2xf64>
    // A constant matrix must be symmetric with a zero diagonal.
    // CHECK: %[[A:.*]] = arith.constant dense<{{\[\[}}0.000000e+00, 5.000000e-01], [5.000000e-01, 0.000000e+00]]> : vector<2x2xf64>
    %a = arith.constant dense<[[0.0, 0.5], [0.5, 0.0]]> : vector<2x2xf64>
    // CHECK: qvec.global zz(%[[A]]) %[[Z]] : vector<2x!qco.qubit>, vector<2x2xf64>
    %z2 = qvec.global zz(%a) %z : vector<2x!qco.qubit>, vector<2x2xf64>

    func.return
}

// CHECK-LABEL: @measurement
func.func @measurement(%qs: vector<2x!qco.qubit>) {
    // CHECK: %{{.*}}, %{{.*}} = qvec.mz %{{.*}} : vector<2x!qco.qubit> -> vector<2xi1>
    %qs_out, %result = qvec.mz %qs : vector<2x!qco.qubit> -> vector<2xi1>

    func.return
}
