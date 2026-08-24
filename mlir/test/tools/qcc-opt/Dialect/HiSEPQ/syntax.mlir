// RUN: qcc-opt %s | FileCheck %s

// CHECK-LABEL: @single_gates
func.func @single_gates(%qs: vector<2x!qc.qubit>) {
    // CHECK: hisepq.single h
    hisepq.single h %qs : vector<2x!qc.qubit>
    // CHECK: hisepq.single x
    hisepq.single x %qs : vector<2x!qc.qubit>
    // CHECK: hisepq.single s
    hisepq.single s %qs : vector<2x!qc.qubit>
    // CHECK: hisepq.single sdg
    hisepq.single sdg %qs : vector<2x!qc.qubit>
    // ... there are more but lets stop here.

    func.return
}

// CHECK-LABEL: @pair_gates
func.func @pair_gates(%as: vector<2x!qc.qubit>, %bs: vector<2x!qc.qubit>) {
    // CHECK: hisepq.pair cx
    hisepq.pair cx %as, %bs : vector<2x!qc.qubit>
    // CHECK: hisepq.pair iswap
    hisepq.pair iswap %as, %bs : vector<2x!qc.qubit>
    // ... there are more but lets stop here.

    func.return
}

// CHECK-LABEL: @measurement
func.func @measurement(%qs: vector<2x!qc.qubit>) {
    // CHECK: hisepq.mz
    %result = hisepq.mz %qs : vector<2x!qc.qubit> -> vector<2xi1>

    func.return
}
