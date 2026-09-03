// RUN: qcc-opt %s -qvec-merge=max-vf=2 --split-input-file | FileCheck %s --check-prefix=CHECK-CAPPED
// RUN: qcc-opt %s -qvec-merge=max-vf=0 --split-input-file | FileCheck %s --check-prefix=CHECK-UNCAPPED

// Coverage for the `max-vf` option. The option has two regimes -- a cap of `k >= 1` and the unbounded `0`.

// CHECK-CAPPED-LABEL: func.func @single_gates
// CHECK-UNCAPPED-LABEL: func.func @single_gates
func.func @single_gates() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %q2 = qco.static 2 : !qco.qubit
    %q3 = qco.static 3 : !qco.qubit
    %q4 = qco.static 4 : !qco.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qco.qubit>
    %v2 = vector.from_elements %q2 : vector<1x!qco.qubit>
    %v3 = vector.from_elements %q3 : vector<1x!qco.qubit>
    %v4 = vector.from_elements %q4 : vector<1x!qco.qubit>

    %h0 = qvec.single h %v0 : vector<1x!qco.qubit>
    %h1 = qvec.single h %v1 : vector<1x!qco.qubit>
    %h2 = qvec.single h %v2 : vector<1x!qco.qubit>
    %h3 = qvec.single h %v3 : vector<1x!qco.qubit>
    %h4 = qvec.single h %v4 : vector<1x!qco.qubit>

    func.return
}

// Groups are filled in IR order, so the split falls between q1 and q2.
// CHECK-CAPPED-DAG:     %[[Q0:.*]] = qco.static 0
// CHECK-CAPPED-DAG:     %[[Q1:.*]] = qco.static 1
// CHECK-CAPPED-DAG:     %[[Q2:.*]] = qco.static 2
// CHECK-CAPPED-DAG:     %[[Q3:.*]] = qco.static 3
// CHECK-CAPPED:         %[[A:.*]] = vector.from_elements %[[Q0]], %[[Q1]] : vector<2x!qco.qubit>
// CHECK-CAPPED:         qvec.single h %[[A]] : vector<2x!qco.qubit>
// CHECK-CAPPED:         %[[B:.*]] = vector.from_elements %[[Q2]], %[[Q3]] : vector<2x!qco.qubit>
// CHECK-CAPPED:         qvec.single h %[[B]] : vector<2x!qco.qubit>
// CHECK-CAPPED:         qvec.single h %{{.*}} : vector<1x!qco.qubit>
// CHECK-CAPPED-NOT:     qvec.

// CHECK-UNCAPPED:       %[[V:.*]] = vector.from_elements %{{.*}} : vector<5x!qco.qubit>
// CHECK-UNCAPPED:       qvec.single h %[[V]] : vector<5x!qco.qubit>
// CHECK-UNCAPPED-NOT:   qvec.

// -----

// CHECK-CAPPED-LABEL: func.func @member_wider_than_cap
// CHECK-UNCAPPED-LABEL: func.func @member_wider_than_cap
func.func @member_wider_than_cap() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %q2 = qco.static 2 : !qco.qubit
    %q3 = qco.static 3 : !qco.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %wide = vector.from_elements %q1, %q2, %q3 : vector<3x!qco.qubit>

    %h0 = qvec.single h %v0 : vector<1x!qco.qubit>
    %h1 = qvec.single h %wide : vector<3x!qco.qubit>

    func.return
}

// Nothing merges at all.
// CHECK-CAPPED:         qvec.single h %{{.*}} : vector<1x!qco.qubit>
// CHECK-CAPPED:         qvec.single h %{{.*}} : vector<3x!qco.qubit>
// CHECK-CAPPED-NOT:     qvec.

// CHECK-UNCAPPED:       %[[V:.*]] = vector.from_elements %{{.*}} : vector<4x!qco.qubit>
// CHECK-UNCAPPED:       qvec.single h %[[V]] : vector<4x!qco.qubit>
// CHECK-UNCAPPED-NOT:   qvec.

// -----

// CHECK-CAPPED-LABEL: func.func @pair_gates
// CHECK-UNCAPPED-LABEL: func.func @pair_gates
func.func @pair_gates() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %q2 = qco.static 2 : !qco.qubit
    %q3 = qco.static 3 : !qco.qubit
    %q4 = qco.static 4 : !qco.qubit
    %q5 = qco.static 5 : !qco.qubit
    %a0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %b0 = vector.from_elements %q1 : vector<1x!qco.qubit>
    %c0 = vector.from_elements %q2 : vector<1x!qco.qubit>
    %d0 = vector.from_elements %q3 : vector<1x!qco.qubit>
    %e0 = vector.from_elements %q4 : vector<1x!qco.qubit>
    %f0 = vector.from_elements %q5 : vector<1x!qco.qubit>

    %a1, %b1 = qvec.pair cx %a0, %b0 : vector<1x!qco.qubit>
    %c1, %d1 = qvec.pair cx %c0, %d0 : vector<1x!qco.qubit>
    %e1, %f1 = qvec.pair cx %e0, %f0 : vector<1x!qco.qubit>

    func.return
}

// CHECK-CAPPED-DAG:     %[[Q0:.*]] = qco.static 0
// CHECK-CAPPED-DAG:     %[[Q1:.*]] = qco.static 1
// CHECK-CAPPED-DAG:     %[[Q2:.*]] = qco.static 2
// CHECK-CAPPED-DAG:     %[[Q3:.*]] = qco.static 3
// CHECK-CAPPED:         %[[L:.*]] = vector.from_elements %[[Q0]], %[[Q2]] : vector<2x!qco.qubit>
// CHECK-CAPPED:         %[[R:.*]] = vector.from_elements %[[Q1]], %[[Q3]] : vector<2x!qco.qubit>
// CHECK-CAPPED:         qvec.pair cx %[[L]], %[[R]] : vector<2x!qco.qubit>
// CHECK-CAPPED:         qvec.pair cx %{{.*}}, %{{.*}} : vector<1x!qco.qubit>
// CHECK-CAPPED-NOT:     qvec.

// CHECK-UNCAPPED:       qvec.pair cx %{{.*}}, %{{.*}} : vector<3x!qco.qubit>
// CHECK-UNCAPPED-NOT:   qvec.
