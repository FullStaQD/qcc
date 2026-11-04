// RUN: qcc-opt %s | FileCheck %s
// RUN: qcc-opt %s --mlir-print-op-generic | qcc-opt | FileCheck %s

// CHECK-LABEL: @single_gates
func.func @single_gates(%qs: vector<2x!qco.qubit>) {
    // CHECK: %[[H:.*]] = qvec.single h %{{.*}} : vector<2x!qco.qubit>
    %h = qvec.single h %qs : vector<2x!qco.qubit>
    // CHECK: %[[X:.*]] = qvec.single x %[[H]]
    %x = qvec.single x %h : vector<2x!qco.qubit>
    // CHECK: %[[S:.*]] = qvec.single s %[[X]]
    %s = qvec.single s %x : vector<2x!qco.qubit>
    // CHECK: %[[SDG:.*]] = qvec.single sdg %[[S]]
    %sdg = qvec.single sdg %s : vector<2x!qco.qubit>
    // CHECK: qvec.single sx %[[SDG]]
    %sx = qvec.single sx %sdg : vector<2x!qco.qubit>
    // ... there are more but let's stop here.

    func.return
}

// CHECK-LABEL: @parametrised_single_gates
func.func @parametrised_single_gates(%qs: vector<2x!qco.qubit>, %theta: vector<2xf64>) {
    // CHECK: %[[RX:.*]] = qvec.single rx(%{{.*}}) %{{.*}} : vector<2xf64>, vector<2x!qco.qubit>
    %rx = qvec.single rx(%theta) %qs : vector<2xf64>, vector<2x!qco.qubit>
    // CHECK: %[[RY:.*]] = qvec.single ry(%{{.*}}) %[[RX]] : vector<2xf64>, vector<2x!qco.qubit>
    %ry = qvec.single ry(%theta) %rx : vector<2xf64>, vector<2x!qco.qubit>
    // CHECK: %[[RZ:.*]] = qvec.single rz(%{{.*}}) %[[RY]] : vector<2xf64>, vector<2x!qco.qubit>
    %rz = qvec.single rz(%theta) %ry : vector<2xf64>, vector<2x!qco.qubit>
    // Three parameters share one type.
    // CHECK: %[[U:.*]] = qvec.single u_zxz(%{{.*}}, %{{.*}}, %{{.*}}) %[[RZ]] : vector<2xf64>, vector<2x!qco.qubit>
    %u = qvec.single u_zxz(%theta, %theta, %theta) %rz : vector<2xf64>, vector<2x!qco.qubit>
    // CHECK: qvec.single u_zyz(%{{.*}}, %{{.*}}, %{{.*}}) %[[U]] : vector<2xf64>, vector<2x!qco.qubit>
    %u2 = qvec.single u_zyz(%theta, %theta, %theta) %u : vector<2xf64>, vector<2x!qco.qubit>

    func.return
}

// CHECK-LABEL: @pair_gates
func.func @pair_gates(%as: vector<2x!qco.qubit>, %bs: vector<2x!qco.qubit>, %theta: vector<2xf64>) {
    // CHECK: %[[CA:.*]], %[[CB:.*]] = qvec.pair cx %{{.*}}, %{{.*}} : vector<2x!qco.qubit>
    %ca, %cb = qvec.pair cx %as, %bs : vector<2x!qco.qubit>
    // CHECK: %[[IA:.*]], %[[IB:.*]] = qvec.pair iswap %[[CA]], %[[CB]]
    %ia, %ib = qvec.pair iswap %ca, %cb : vector<2x!qco.qubit>
    // CHECK: %[[RA:.*]], %[[RB:.*]] = qvec.pair rzz(%{{.*}}) %[[IA]], %[[IB]] : vector<2xf64>, vector<2x!qco.qubit>
    %ra, %rb = qvec.pair rzz(%theta) %ia, %ib : vector<2xf64>, vector<2x!qco.qubit>
    // CHECK: %[[PA:.*]], %[[PB:.*]] = qvec.pair cp(%{{.*}}) %[[RA]], %[[RB]] : vector<2xf64>, vector<2x!qco.qubit>
    %pa, %pb = qvec.pair cp(%theta) %ra, %rb : vector<2xf64>, vector<2x!qco.qubit>
    // CHECK: %[[SA:.*]], %[[SB:.*]] = qvec.pair swap %[[PA]], %[[PB]] : vector<2x!qco.qubit>
    %sa, %sb = qvec.pair swap %pa, %pb : vector<2x!qco.qubit>
    // CHECK: qvec.pair crz(%{{.*}}) %[[SA]], %[[SB]] : vector<2xf64>, vector<2x!qco.qubit>
    %za, %zb = qvec.pair crz(%theta) %sa, %sb : vector<2xf64>, vector<2x!qco.qubit>
    // ... there are more but let's stop here.

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

// CHECK-LABEL: @measure_and_reset
func.func @measure_and_reset(%qs: vector<2x!qco.qubit>) {
    // CHECK: %[[MZ:.*]], %{{.*}} = qvec.measure z %{{.*}} : vector<2x!qco.qubit> -> vector<2xi1>
    %mz, %bits_z = qvec.measure z %qs : vector<2x!qco.qubit> -> vector<2xi1>
    // CHECK: %[[RZ:.*]] = qvec.reset z %[[MZ]] : vector<2x!qco.qubit>
    %rz = qvec.reset z %mz : vector<2x!qco.qubit>
    // CHECK: %[[RX:.*]] = qvec.reset x %[[RZ]] : vector<2x!qco.qubit>
    %rx = qvec.reset x %rz : vector<2x!qco.qubit>
    // CHECK: qvec.measure x %[[RX]] : vector<2x!qco.qubit> -> vector<2xi1>
    %mx, %bits_x = qvec.measure x %rx : vector<2x!qco.qubit> -> vector<2xi1>

    func.return
}
