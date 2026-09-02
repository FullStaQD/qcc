// RUN: qcc-opt %s -qvec-merge --split-input-file | FileCheck %s

// CHECK-LABEL: func.func @one_layer
func.func @one_layer() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %q2 = qco.static 2 : !qco.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qco.qubit>
    %v2 = vector.from_elements %q2 : vector<1x!qco.qubit>

    %h0 = qvec.single h %v0 : vector<1x!qco.qubit>
    %h1 = qvec.single h %v1 : vector<1x!qco.qubit>
    %h2 = qvec.single h %v2 : vector<1x!qco.qubit>

    func.return
}

// CHECK-DAG:     %[[Q0:.*]] = qco.static 0
// CHECK-DAG:     %[[Q1:.*]] = qco.static 1
// CHECK-DAG:     %[[Q2:.*]] = qco.static 2
// CHECK:         %[[V0:.*]] = vector.from_elements %[[Q0]], %[[Q1]], %[[Q2]] : vector<3x!qco.qubit>
// CHECK:         qvec.single h %[[V0]] : vector<3x!qco.qubit>
// CHECK-NOT:     qvec.

// -----

// CHECK-LABEL: func.func @merge_across_obstacle
func.func @merge_across_obstacle() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %q2 = qco.static 2 : !qco.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qco.qubit>
    %v2 = vector.from_elements %q2 : vector<1x!qco.qubit>

    %h0 = qvec.single h %v0 : vector<1x!qco.qubit>
    %x1 = qvec.single x %v1 : vector<1x!qco.qubit> // despite obstacle we can still merge the hadamards
    %h2 = qvec.single h %v2 : vector<1x!qco.qubit>

    func.return
}

// CHECK-DAG:     %[[Q0:.*]] = qco.static 0
// CHECK-DAG:     %[[Q2:.*]] = qco.static 2
// CHECK:         %[[V0:.*]] = vector.from_elements %[[Q0]], %[[Q2]] : vector<2x!qco.qubit>
// CHECK:         qvec.single h %[[V0]] : vector<2x!qco.qubit>
// CHECK:         qvec.single x %{{.*}} : vector<1x!qco.qubit>

// -----

// CHECK-LABEL: func.func @dependent_singles
func.func @dependent_singles() {
    %q0 = qco.static 0 : !qco.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>

    %v1 = qvec.single h %v0 : vector<1x!qco.qubit>
    %v2 = qvec.single h %v1 : vector<1x!qco.qubit>
    %v3 = qvec.single h %v2 : vector<1x!qco.qubit>

    func.return
}

// Do not merge!
// CHECK:         %[[V1:.*]] = qvec.single h %{{.*}} : vector<1x!qco.qubit>
// CHECK:         %[[V2:.*]] = qvec.single h %[[V1]] : vector<1x!qco.qubit>
// CHECK:                    = qvec.single h %[[V2]] : vector<1x!qco.qubit>

// -----

// CHECK-LABEL: func.func @dependent_pairs
func.func @dependent_pairs() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qco.qubit>

    %a, %b = qvec.pair cx %v0, %v1 : vector<1x!qco.qubit>
    %c, %d = qvec.pair cx %v1, %v0 : vector<1x!qco.qubit>

    func.return
}

// Do not merge!
// CHECK:         qvec.pair cx %{{.*}}, %{{.*}} : vector<1x!qco.qubit>
// CHECK:         qvec.pair cx %{{.*}}, %{{.*}} : vector<1x!qco.qubit>

// -----

// CHECK-LABEL: func.func @interleaved_layers
func.func @interleaved_layers() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %q2 = qco.static 2 : !qco.qubit
    %q3 = qco.static 3 : !qco.qubit

    // h(0) cx(0; 1)
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %h0 = qvec.single h %v0 : vector<1x!qco.qubit>
    %t0 = vector.from_elements %q1 : vector<1x!qco.qubit>
    %c0, %d0 = qvec.pair cx %h0, %t0 : vector<1x!qco.qubit>

    // h(2) cx(2; 3)
    %v1 = vector.from_elements %q2 : vector<1x!qco.qubit>
    %h1 = qvec.single h %v1 : vector<1x!qco.qubit>
    %t1 = vector.from_elements %q3 : vector<1x!qco.qubit>
    %c1, %d1 = qvec.pair cx %h1, %t1 : vector<1x!qco.qubit>

    func.return
}

// CHECK-DAG:     %[[Q0:.*]] = qco.static 0
// CHECK-DAG:     %[[Q1:.*]] = qco.static 1
// CHECK-DAG:     %[[Q2:.*]] = qco.static 2
// CHECK-DAG:     %[[Q3:.*]] = qco.static 3

// h(0, 2) cx(0, 2; 1, 3)
// CHECK:         %[[C0:.*]] = vector.from_elements %[[Q0]], %[[Q2]] : vector<2x!qco.qubit>
// CHECK:         %[[C1:.*]] = qvec.single h %[[C0]] : vector<2x!qco.qubit>
// CHECK:         %[[T0:.*]] = vector.from_elements %[[Q1]], %[[Q3]] : vector<2x!qco.qubit>
// CHECK:                    = qvec.pair cx %[[C1]], %[[T0]] : vector<2x!qco.qubit>

// -----

// Measurements pack like gates do, and across both operands of the `pair` they follow: all four
// qubits are measured by one instruction.

// CHECK-LABEL: func.func @measurements
func.func @measurements() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %q2 = qco.static 2 : !qco.qubit
    %q3 = qco.static 3 : !qco.qubit
    %a0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %b0 = vector.from_elements %q1 : vector<1x!qco.qubit>
    %c0 = vector.from_elements %q2 : vector<1x!qco.qubit>
    %d0 = vector.from_elements %q3 : vector<1x!qco.qubit>

    %a1, %b1 = qvec.pair cx %a0, %b0 : vector<1x!qco.qubit>
    %c1, %d1 = qvec.pair cx %c0, %d0 : vector<1x!qco.qubit>

    %ao, %a2 = qvec.mz %a1 : vector<1x!qco.qubit> -> vector<1xi1>
    %bo, %b2 = qvec.mz %b1 : vector<1x!qco.qubit> -> vector<1xi1>
    %do, %c2 = qvec.mz %c1 : vector<1x!qco.qubit> -> vector<1xi1>
    %eo, %d2 = qvec.mz %d1 : vector<1x!qco.qubit> -> vector<1xi1>

    func.return
}

// CHECK:         qvec.pair cx %{{.*}}, %{{.*}} : vector<2x!qco.qubit>
// CHECK-NOT:     qvec.pair cx
// CHECK-COUNT-4: vector.extract
// CHECK:         %[[V0:.*]] = vector.from_elements
// CHECK:         qvec.mz %[[V0]] : vector<4x!qco.qubit> -> vector<4xi1>
// CHECK-NOT:     qvec.mz

// -----

// CHECK-LABEL: func.func @measurement_bits_extracted_for_user
func.func @measurement_bits_extracted_for_user(%k: i1) -> i1 {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %a0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %b0 = vector.from_elements %q1 : vector<1x!qco.qubit>

    %a1, %r0 = qvec.mz %a0 : vector<1x!qco.qubit> -> vector<1xi1>
    %r00 = vector.extract %r0[0] : i1 from vector<1xi1>
    %xori = arith.xori %r00, %k : i1

    %b1, %t0 = qvec.mz %b0 : vector<1x!qco.qubit> -> vector<1xi1>
    %t00 = vector.extract %t0[0] : i1 from vector<1xi1>
    %andi = arith.andi %xori, %t00 : i1

    func.return %andi : i1
}

// Measure with a single instruction, then extract the bits where they are used.
// CHECK:         %{{.*}}, %[[BITS:.*]] = qvec.mz %{{.*}} : vector<2x!qco.qubit> -> vector<2xi1>
// CHECK-DAG:     %[[R0:.*]] = vector.extract %[[BITS]][0] : i1 from vector<2xi1>
// CHECK-DAG:     %[[R1:.*]] = vector.extract %[[BITS]][1] : i1 from vector<2xi1>
// CHECK-DAG:     %[[N:.*]] = arith.xori %[[R0]], %{{.*}} : i1
// CHECK:         arith.andi %[[N]], %[[R1]] : i1

// -----

// CHECK-LABEL: func.func @qubits_maybe_not_disjoint
func.func @qubits_maybe_not_disjoint(%qs: vector<2x!qco.qubit>, %rs: vector<2x!qco.qubit>) {
    %a = qvec.single h %qs : vector<2x!qco.qubit>
    %b = qvec.single h %rs : vector<2x!qco.qubit>
    func.return
}

// We must not merge because we cannot prove the qubits are disjoint:
// CHECK:         qvec.single h %{{.*}} : vector<2x!qco.qubit>
// CHECK:         qvec.single h %{{.*}} : vector<2x!qco.qubit>

// -----

// FIXME: remove this test at the end

// CHECK-LABEL: func.func @untraceable_producer
func.func @untraceable_producer() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qco.qubit>

    %h0 = qvec.single h %v0 : vector<1x!qco.qubit>
    %h1 = qvec.single h %v1 : vector<1x!qco.qubit>

    // A scalar gate hides where the qubit came from, so `%h2` must not join a layer of its own producer.
    %e0 = vector.extract %h0[0] : !qco.qubit from vector<1x!qco.qubit>
    %x0 = qco.x %e0 : !qco.qubit -> !qco.qubit
    %w0 = vector.from_elements %x0 : vector<1x!qco.qubit>
    %h2 = qvec.single h %w0 : vector<1x!qco.qubit>

    func.return
}

// The two independent hadamards merge, the one behind the opaque gate stays on its own.
// CHECK:         qvec.single h %{{.*}} : vector<2x!qco.qubit>
// CHECK:         qco.x
// CHECK:         qvec.single h %{{.*}} : vector<1x!qco.qubit>
// CHECK-NOT:     qvec.

// -----

// FIXME: remove this test at the end

// CHECK-LABEL: func.func @stale_layer_propagates
func.func @stale_layer_propagates() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %a0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %b0 = vector.from_elements %q1 : vector<1x!qco.qubit>

    // A chain on q0, so %a2 genuinely lives in layer 1.
    %a1 = qvec.single h %a0 : vector<1x!qco.qubit> // layer 0
    %a2 = qvec.single h %a1 : vector<1x!qco.qubit> // layer 1

    // An opaque hop, hiding from the layering that everything below depends on %a2.
    %a2_0 = vector.extract %a2[0] : !qco.qubit from vector<1x!qco.qubit>
    %x = qco.x %a2_0 : !qco.qubit -> !qco.qubit
    %a3 = vector.from_elements %x : vector<1x!qco.qubit>

    // Slot 0 is the opaque q0 line, slot 1 is a clean q1. Only slot 0 loses its producer, so the operation
    // lands in layer 0 although it belongs in layer 2.
    %a4, %b1 = qvec.pair cx %a3, %b0 : vector<1x!qco.qubit> // layer 0 (wrong)

    // Reading the clean slot, this one has complete producers and identifiable qubits, so neither guard in the
    // layering stops it. Its layer is 1, taken from the stale layer above, and it shares that layer and gate kind
    // with %a2 -- on which it depends through the opaque hop.
    %b2 = qvec.single h %b1 : vector<1x!qco.qubit> // layer 1 (wrong)

    func.return
}

// Merging %a2 and %b2 would move %b2 ahead of an operation it depends on. Nothing merges, because a candidate can
// only join a group if its operands can be made available at the group's first member, and reaching back past a
// `qvec` operation would mean hoisting one -- which is never allowed, as they all read and write memory.
// CHECK:         %[[M0:.*]] = qvec.single h %{{.*}} : vector<1x!qco.qubit>
// CHECK:         %[[M1:.*]] = qvec.single h %[[M0]] : vector<1x!qco.qubit>
// CHECK:         qco.x
// CHECK:         %[[LHS:.*]], %[[RHS:.*]] = qvec.pair cx %{{.*}}, %{{.*}} : vector<1x!qco.qubit>
// CHECK:         qvec.single h %[[RHS]] : vector<1x!qco.qubit>
// CHECK-NOT:     qvec.

// -----

// CHECK-LABEL: func.func @wide_member_slice_is_one_op
func.func @wide_member_slice_is_one_op() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %q2 = qco.static 2 : !qco.qubit
    %q3 = qco.static 3 : !qco.qubit
    %a0 = vector.from_elements %q0, %q1 : vector<2x!qco.qubit>
    %b0 = vector.from_elements %q2, %q3 : vector<2x!qco.qubit>

    %a1 = qvec.single h %a0 : vector<2x!qco.qubit> // layer 0
    %b1 = qvec.single h %b0 : vector<2x!qco.qubit> // layer 0

    // Different gate kinds, so these two never merge and their operands stay in the IR to be looked at.
    %a2 = qvec.single x %a1 : vector<2x!qco.qubit> // layer 1
    %b2 = qvec.single y %b1 : vector<2x!qco.qubit> // layer 1

    func.return
}

// Handing a member its share of the merged result takes one operation, whatever the member's width.
// CHECK:         %[[H:.*]] = qvec.single h %{{.*}} : vector<4x!qco.qubit>
// CHECK:         %[[S0:.*]] = vector.extract_strided_slice %[[H]] {offsets = [0], sizes = [2], strides = [1]}
// CHECK:         %[[S1:.*]] = vector.extract_strided_slice %[[H]] {offsets = [2], sizes = [2], strides = [1]}
// CHECK:         qvec.single x %[[S0]] : vector<2x!qco.qubit>
// CHECK:         qvec.single y %[[S1]] : vector<2x!qco.qubit>
