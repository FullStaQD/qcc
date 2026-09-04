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

// CHECK-LABEL: @pair_gates
func.func @pair_gates(%as: vector<2x!qco.qubit>, %bs: vector<2x!qco.qubit>) {
    // CHECK: %[[CA:.*]], %[[CB:.*]] = qvec.pair cx %{{.*}}, %{{.*}} : vector<2x!qco.qubit>
    %ca, %cb = qvec.pair cx %as, %bs : vector<2x!qco.qubit>
    // CHECK: qvec.pair iswap %[[CA]], %[[CB]]
    %ia, %ib = qvec.pair iswap %ca, %cb : vector<2x!qco.qubit>
    // ... there are more but lets stop here.

    func.return
}

// CHECK-LABEL: @measurement
func.func @measurement(%qs: vector<2x!qco.qubit>) {
    // CHECK: %{{.*}}, %{{.*}} = qvec.mz %{{.*}} : vector<2x!qco.qubit> -> vector<2xi1>
    %qs_out, %result = qvec.mz %qs : vector<2x!qco.qubit> -> vector<2xi1>

    func.return
}
