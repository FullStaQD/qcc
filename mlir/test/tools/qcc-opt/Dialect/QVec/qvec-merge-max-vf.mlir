// RUN: qcc-opt %s -qvec-merge=max-vf=2 --split-input-file | FileCheck %s --check-prefix=CHECK-CAPPED
// RUN: qcc-opt %s -qvec-merge=max-vf=0 --split-input-file | FileCheck %s --check-prefix=CHECK-UNCAPPED

// Coverage for the `max-vf` option. The option has two regimes -- a cap of `k >= 1` and the unbounded `0`.

// CHECK-CAPPED-LABEL: func.func @single_gates
// CHECK-UNCAPPED-LABEL: func.func @single_gates
func.func @single_gates() {
    %q0, %q1, %q2, %q3, %q4 = qcc.static [0, 1, 2, 3, 4] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qcc.qubit>
    %v2 = vector.from_elements %q2 : vector<1x!qcc.qubit>
    %v3 = vector.from_elements %q3 : vector<1x!qcc.qubit>
    %v4 = vector.from_elements %q4 : vector<1x!qcc.qubit>

    %h0 = qvec.single h %v0 : vector<1x!qcc.qubit>
    %h1 = qvec.single h %v1 : vector<1x!qcc.qubit>
    %h2 = qvec.single h %v2 : vector<1x!qcc.qubit>
    %h3 = qvec.single h %v3 : vector<1x!qcc.qubit>
    %h4 = qvec.single h %v4 : vector<1x!qcc.qubit>

    func.return
}

// Groups are filled in IR order, so the split falls between q1 and q2.
// CHECK-CAPPED:         %[[Q:.*]]:5 = qcc.static [0, 1, 2, 3, 4] : !qcc.qubit
// CHECK-CAPPED:         %[[A:.*]] = vector.from_elements %[[Q]]#0, %[[Q]]#1 : vector<2x!qcc.qubit>
// CHECK-CAPPED:         qvec.single h %[[A]] : vector<2x!qcc.qubit>
// CHECK-CAPPED:         %[[B:.*]] = vector.from_elements %[[Q]]#2, %[[Q]]#3 : vector<2x!qcc.qubit>
// CHECK-CAPPED:         qvec.single h %[[B]] : vector<2x!qcc.qubit>
// CHECK-CAPPED:         qvec.single h %{{.*}} : vector<1x!qcc.qubit>
// CHECK-CAPPED-NOT:     qvec.

// CHECK-UNCAPPED:       %[[V:.*]] = vector.from_elements %{{.*}} : vector<5x!qcc.qubit>
// CHECK-UNCAPPED:       qvec.single h %[[V]] : vector<5x!qcc.qubit>
// CHECK-UNCAPPED-NOT:   qvec.

// -----

// CHECK-CAPPED-LABEL: func.func @member_wider_than_cap
// CHECK-UNCAPPED-LABEL: func.func @member_wider_than_cap
func.func @member_wider_than_cap() {
    %q0, %q1, %q2, %q3 = qcc.static [0, 1, 2, 3] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %wide = vector.from_elements %q1, %q2, %q3 : vector<3x!qcc.qubit>

    %h0 = qvec.single h %v0 : vector<1x!qcc.qubit>
    %h1 = qvec.single h %wide : vector<3x!qcc.qubit>

    func.return
}

// Nothing merges at all.
// CHECK-CAPPED:         qvec.single h %{{.*}} : vector<1x!qcc.qubit>
// CHECK-CAPPED:         qvec.single h %{{.*}} : vector<3x!qcc.qubit>
// CHECK-CAPPED-NOT:     qvec.

// CHECK-UNCAPPED:       %[[V:.*]] = vector.from_elements %{{.*}} : vector<4x!qcc.qubit>
// CHECK-UNCAPPED:       qvec.single h %[[V]] : vector<4x!qcc.qubit>
// CHECK-UNCAPPED-NOT:   qvec.

// -----

// CHECK-CAPPED-LABEL: func.func @pair_gates
// CHECK-UNCAPPED-LABEL: func.func @pair_gates
func.func @pair_gates() {
    %q0, %q1, %q2, %q3, %q4, %q5 = qcc.static [0, 1, 2, 3, 4, 5] : !qcc.qubit
    %a0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %b0 = vector.from_elements %q1 : vector<1x!qcc.qubit>
    %c0 = vector.from_elements %q2 : vector<1x!qcc.qubit>
    %d0 = vector.from_elements %q3 : vector<1x!qcc.qubit>
    %e0 = vector.from_elements %q4 : vector<1x!qcc.qubit>
    %f0 = vector.from_elements %q5 : vector<1x!qcc.qubit>

    %a1, %b1 = qvec.pair cx %a0, %b0 : vector<1x!qcc.qubit>
    %c1, %d1 = qvec.pair cx %c0, %d0 : vector<1x!qcc.qubit>
    %e1, %f1 = qvec.pair cx %e0, %f0 : vector<1x!qcc.qubit>

    func.return
}

// CHECK-CAPPED:         %[[Q:.*]]:6 = qcc.static [0, 1, 2, 3, 4, 5] : !qcc.qubit
// CHECK-CAPPED:         %[[L:.*]] = vector.from_elements %[[Q]]#0, %[[Q]]#2 : vector<2x!qcc.qubit>
// CHECK-CAPPED:         %[[R:.*]] = vector.from_elements %[[Q]]#1, %[[Q]]#3 : vector<2x!qcc.qubit>
// CHECK-CAPPED:         qvec.pair cx %[[L]], %[[R]] : vector<2x!qcc.qubit>
// CHECK-CAPPED:         qvec.pair cx %{{.*}}, %{{.*}} : vector<1x!qcc.qubit>
// CHECK-CAPPED-NOT:     qvec.

// CHECK-UNCAPPED:       qvec.pair cx %{{.*}}, %{{.*}} : vector<3x!qcc.qubit>
// CHECK-UNCAPPED-NOT:   qvec.
