// RUN: qcc-opt %s | FileCheck %s

// CHECK-LABEL: @single_gates
func.func @single_gates(%qs: vector<2x!qco.qubit>) {
    // CHECK: %[[H:.*]] = hisepq.single h %{{.*}} : vector<2x!qco.qubit>
    %h = hisepq.single h %qs : vector<2x!qco.qubit>
    // CHECK: %[[X:.*]] = hisepq.single x %[[H]]
    %x = hisepq.single x %h : vector<2x!qco.qubit>
    // CHECK: %[[S:.*]] = hisepq.single s %[[X]]
    %s = hisepq.single s %x : vector<2x!qco.qubit>
    // CHECK: hisepq.single sdg %[[S]]
    %sdg = hisepq.single sdg %s : vector<2x!qco.qubit>
    // ... there are more but lets stop here.

    func.return
}

// CHECK-LABEL: @pair_gates
func.func @pair_gates(%as: vector<2x!qco.qubit>, %bs: vector<2x!qco.qubit>) {
    // CHECK: %[[CA:.*]], %[[CB:.*]] = hisepq.pair cx %{{.*}}, %{{.*}} : vector<2x!qco.qubit>
    %ca, %cb = hisepq.pair cx %as, %bs : vector<2x!qco.qubit>
    // CHECK: hisepq.pair iswap %[[CA]], %[[CB]]
    %ia, %ib = hisepq.pair iswap %ca, %cb : vector<2x!qco.qubit>
    // ... there are more but lets stop here.

    func.return
}

// CHECK-LABEL: @measurement
func.func @measurement(%qs: vector<2x!qco.qubit>) {
    // CHECK: %{{.*}}, %{{.*}} = hisepq.mz %{{.*}} : vector<2x!qco.qubit> -> vector<2xi1>
    %qs_out, %result = hisepq.mz %qs : vector<2x!qco.qubit> -> vector<2xi1>

    func.return
}
