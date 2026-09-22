// RUN: qcc-opt %s -qvec-to-rzz --split-input-file | FileCheck %s

// The decompositions below were checked numerically against the pair gates' unitaries (up to a global phase).

// CHECK-LABEL: func.func @cz
func.func @cz(%as: vector<2x!qco.qubit>, %bs: vector<2x!qco.qubit>) -> (vector<2x!qco.qubit>, vector<2x!qco.qubit>) {
    %a, %b = qvec.pair cz %as, %bs : vector<2x!qco.qubit>
    func.return %a, %b : vector<2x!qco.qubit>, vector<2x!qco.qubit>
}

// cz = (rz(-pi/2) (x) rz(-pi/2)) * rzz(pi/2)
// CHECK-DAG:     %[[P:.*]] = arith.constant dense<1.5707963267948966> : vector<2xf64>
// CHECK-DAG:     %[[M:.*]] = arith.constant dense<-1.5707963267948966> : vector<2xf64>
// CHECK:         %[[A:.*]], %[[B:.*]] = qvec.pair rzz(%[[P]]) %{{.*}}, %{{.*}} : vector<2x!qco.qubit>, vector<2xf64>
// CHECK:         %[[A1:.*]] = qvec.single rz(%[[M]]) %[[A]] : vector<2x!qco.qubit>, vector<2xf64>
// CHECK:         %[[B1:.*]] = qvec.single rz(%[[M]]) %[[B]] : vector<2x!qco.qubit>, vector<2xf64>
// CHECK:         return %[[A1]], %[[B1]]

// -----

// CHECK-LABEL: func.func @cx
func.func @cx(%cs: vector<1x!qco.qubit>, %ts: vector<1x!qco.qubit>) -> (vector<1x!qco.qubit>, vector<1x!qco.qubit>) {
    %c, %t = qvec.pair cx %cs, %ts : vector<1x!qco.qubit>
    func.return %c, %t : vector<1x!qco.qubit>, vector<1x!qco.qubit>
}

// cx = h_t * cz * h_t; the target is the right operand.
// CHECK:         %[[T0:.*]] = qvec.single h %{{.*}} : vector<1x!qco.qubit>
// CHECK:         %[[C1:.*]], %[[T1:.*]] = qvec.pair rzz(%{{.*}}) %{{.*}}, %[[T0]]
// CHECK:         %[[C2:.*]] = qvec.single rz(%{{.*}}) %[[C1]]
// CHECK:         %[[T2:.*]] = qvec.single rz(%{{.*}}) %[[T1]]
// CHECK:         %[[T3:.*]] = qvec.single h %[[T2]]
// CHECK:         return %[[C2]], %[[T3]]

// -----

// CHECK-LABEL: func.func @cy
func.func @cy(%cs: vector<1x!qco.qubit>, %ts: vector<1x!qco.qubit>) -> (vector<1x!qco.qubit>, vector<1x!qco.qubit>) {
    %c, %t = qvec.pair cy %cs, %ts : vector<1x!qco.qubit>
    func.return %c, %t : vector<1x!qco.qubit>, vector<1x!qco.qubit>
}

// cy = s_t * cx * sdg_t
// CHECK:         %[[T0:.*]] = qvec.single sdg %{{.*}} : vector<1x!qco.qubit>
// CHECK:         %[[T1:.*]] = qvec.single h %[[T0]]
// CHECK:         %[[C2:.*]], %[[T2:.*]] = qvec.pair rzz(%{{.*}}) %{{.*}}, %[[T1]]
// CHECK:         %[[C3:.*]] = qvec.single rz(%{{.*}}) %[[C2]]
// CHECK:         %[[T3:.*]] = qvec.single rz(%{{.*}}) %[[T2]]
// CHECK:         %[[T4:.*]] = qvec.single h %[[T3]]
// CHECK:         %[[T5:.*]] = qvec.single s %[[T4]]
// CHECK:         return %[[C3]], %[[T5]]

// -----

// CHECK-LABEL: func.func @cp_constant
func.func @cp_constant(%as: vector<2x!qco.qubit>, %bs: vector<2x!qco.qubit>) -> (vector<2x!qco.qubit>, vector<2x!qco.qubit>) {
    %theta = arith.constant dense<[0.5, 0.25]> : vector<2xf64>
    %a, %b = qvec.pair cp(%theta) %as, %bs : vector<2x!qco.qubit>, vector<2xf64>
    func.return %a, %b : vector<2x!qco.qubit>, vector<2x!qco.qubit>
}

// cp(t) = (rz(t/2) (x) rz(t/2)) * rzz(-t/2), folded lane by lane.
// CHECK-DAG:     %[[MH:.*]] = arith.constant dense<[-2.500000e-01, -1.250000e-01]> : vector<2xf64>
// CHECK-DAG:     %[[H:.*]] = arith.constant dense<[2.500000e-01, 1.250000e-01]> : vector<2xf64>
// CHECK:         %[[A:.*]], %[[B:.*]] = qvec.pair rzz(%[[MH]]) %{{.*}}, %{{.*}} : vector<2x!qco.qubit>, vector<2xf64>
// CHECK:         %[[A1:.*]] = qvec.single rz(%[[H]]) %[[A]]
// CHECK:         %[[B1:.*]] = qvec.single rz(%[[H]]) %[[B]]
// CHECK:         return %[[A1]], %[[B1]]

// -----

// CHECK-LABEL: func.func @cp_dynamic
func.func @cp_dynamic(%as: vector<1x!qco.qubit>, %bs: vector<1x!qco.qubit>, %theta: vector<1xf64>) {
    %a, %b = qvec.pair cp(%theta) %as, %bs : vector<1x!qco.qubit>, vector<1xf64>
    func.return
}

// An SSA angle is scaled at runtime.
// CHECK-DAG:     %[[MHC:.*]] = arith.constant dense<-5.000000e-01> : vector<1xf64>
// CHECK-DAG:     %[[HC:.*]] = arith.constant dense<5.000000e-01> : vector<1xf64>
// CHECK:         %[[MH:.*]] = arith.mulf %arg2, %[[MHC]] : vector<1xf64>
// CHECK:         %[[A:.*]], %[[B:.*]] = qvec.pair rzz(%[[MH]])
// CHECK:         %[[H:.*]] = arith.mulf %arg2, %[[HC]] : vector<1xf64>
// CHECK:         qvec.single rz(%[[H]]) %[[A]]
// CHECK:         qvec.single rz(%[[H]]) %[[B]]

// -----

// CHECK-LABEL: func.func @iswap
func.func @iswap(%as: vector<1x!qco.qubit>, %bs: vector<1x!qco.qubit>) {
    %a, %b = qvec.pair iswap %as, %bs : vector<1x!qco.qubit>
    func.return
}

// iswap = swap * cz * (s (x) s), swap = three cx: four rzz in total, no other pair gate left.
// CHECK:         qvec.single s
// CHECK:         qvec.single s
// CHECK-COUNT-4: qvec.pair rzz
// CHECK-NOT:     qvec.pair

// -----

// CHECK-LABEL: func.func @rzz_stays
func.func @rzz_stays(%as: vector<1x!qco.qubit>, %bs: vector<1x!qco.qubit>, %theta: vector<1xf64>) {
    %a, %b = qvec.pair rzz(%theta) %as, %bs : vector<1x!qco.qubit>, vector<1xf64>
    func.return
}

// CHECK:         qvec.pair rzz(%arg2) %arg0, %arg1
// CHECK-NOT:     qvec.
