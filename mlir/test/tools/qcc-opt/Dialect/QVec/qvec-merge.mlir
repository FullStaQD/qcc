// RUN: qcc-opt %s -qvec-merge --split-input-file | FileCheck %s
// RUN: qcc-opt %s -qvec-merge=max-vf=2 --split-input-file | FileCheck %s --check-prefix=CHECK-VF2
// RUN: qcc-opt %s -qvec-merge=max-vf=64 --split-input-file | FileCheck %s --check-prefix=CHECK-VF64

// FIXME: the max-vf=2 option only tested once, might move into dedicated file.

// CHECK-LABEL: func.func @one_layer
// CHECK-VF2-LABEL: func.func @one_layer
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

// CHECK-VF2:     qvec.single h %{{.*}} : vector<2x!qco.qubit>
// CHECK-VF2:     qvec.single h %{{.*}} : vector<1x!qco.qubit>

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

// Measure with a single instruction, then extract for use in xori and andi.
// CHECK:         %{{.*}}, %[[BITS:.*]] = qvec.mz %{{.*}} : vector<2x!qco.qubit> -> vector<2xi1>
// CHECK-DAG:     %[[R0:.*]] = vector.extract %[[BITS]][0] : i1 from vector<2xi1>
// CHECK-DAG:     %[[R1:.*]] = vector.extract %[[BITS]][1] : i1 from vector<2xi1>
// CHECK:         %[[N:.*]] = arith.xori %[[R0]], %{{.*}} : i1
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

// CHECK-LABEL: func.func @hardware_limit
module {
  func.func @hardware_limit() {
    %q0 = qco.static 0 : !qco.qubit  %q1 = qco.static 1 : !qco.qubit  %q2 = qco.static 2 : !qco.qubit
    %q3 = qco.static 3 : !qco.qubit  %q4 = qco.static 4 : !qco.qubit  %q5 = qco.static 5 : !qco.qubit
    %q6 = qco.static 6 : !qco.qubit  %q7 = qco.static 7 : !qco.qubit  %q8 = qco.static 8 : !qco.qubit
    %q9 = qco.static 9 : !qco.qubit  %q10 = qco.static 10 : !qco.qubit  %q11 = qco.static 11 : !qco.qubit
    %q12 = qco.static 12 : !qco.qubit  %q13 = qco.static 13 : !qco.qubit  %q14 = qco.static 14 : !qco.qubit
    %q15 = qco.static 15 : !qco.qubit  %q16 = qco.static 16 : !qco.qubit  %q17 = qco.static 17 : !qco.qubit
    %q18 = qco.static 18 : !qco.qubit  %q19 = qco.static 19 : !qco.qubit  %q20 = qco.static 20 : !qco.qubit
    %q21 = qco.static 21 : !qco.qubit  %q22 = qco.static 22 : !qco.qubit  %q23 = qco.static 23 : !qco.qubit
    %q24 = qco.static 24 : !qco.qubit  %q25 = qco.static 25 : !qco.qubit  %q26 = qco.static 26 : !qco.qubit
    %q27 = qco.static 27 : !qco.qubit  %q28 = qco.static 28 : !qco.qubit  %q29 = qco.static 29 : !qco.qubit
    %q30 = qco.static 30 : !qco.qubit  %q31 = qco.static 31 : !qco.qubit  %q32 = qco.static 32 : !qco.qubit
    %q33 = qco.static 33 : !qco.qubit  %q34 = qco.static 34 : !qco.qubit  %q35 = qco.static 35 : !qco.qubit
    %q36 = qco.static 36 : !qco.qubit  %q37 = qco.static 37 : !qco.qubit  %q38 = qco.static 38 : !qco.qubit
    %q39 = qco.static 39 : !qco.qubit  %q40 = qco.static 40 : !qco.qubit  %q41 = qco.static 41 : !qco.qubit
    %q42 = qco.static 42 : !qco.qubit  %q43 = qco.static 43 : !qco.qubit  %q44 = qco.static 44 : !qco.qubit
    %q45 = qco.static 45 : !qco.qubit  %q46 = qco.static 46 : !qco.qubit  %q47 = qco.static 47 : !qco.qubit
    %q48 = qco.static 48 : !qco.qubit  %q49 = qco.static 49 : !qco.qubit  %q50 = qco.static 50 : !qco.qubit
    %q51 = qco.static 51 : !qco.qubit  %q52 = qco.static 52 : !qco.qubit  %q53 = qco.static 53 : !qco.qubit
    %q54 = qco.static 54 : !qco.qubit  %q55 = qco.static 55 : !qco.qubit  %q56 = qco.static 56 : !qco.qubit
    %q57 = qco.static 57 : !qco.qubit  %q58 = qco.static 58 : !qco.qubit  %q59 = qco.static 59 : !qco.qubit
    %q60 = qco.static 60 : !qco.qubit  %q61 = qco.static 61 : !qco.qubit  %q62 = qco.static 62 : !qco.qubit
    %q63 = qco.static 63 : !qco.qubit  %q64 = qco.static 64 : !qco.qubit

    %wide = vector.from_elements
        %q0, %q1, %q2, %q3, %q4, %q5, %q6, %q7,
        %q8, %q9, %q10, %q11, %q12, %q13, %q14, %q15,
        %q16, %q17, %q18, %q19, %q20, %q21, %q22, %q23,
        %q24, %q25, %q26, %q27, %q28, %q29, %q30, %q31,
        %q32, %q33, %q34, %q35, %q36, %q37, %q38, %q39,
        %q40, %q41, %q42, %q43, %q44, %q45, %q46, %q47,
        %q48, %q49, %q50, %q51, %q52, %q53, %q54, %q55,
        %q56, %q57, %q58, %q59, %q60, %q61, %q62, %q63
        : vector<64x!qco.qubit>
    %last = vector.from_elements %q64 : vector<1x!qco.qubit>

    %a = qvec.single h %wide : vector<64x!qco.qubit>
    %b = qvec.single h %last : vector<1x!qco.qubit>

    func.return
  }
}

// A cap of 64 splits the 65 qubits over two operations, while an uncapped run merges them into
// one -- the widest group `max-vf` allows is all the pass knows about a machine.
// CHECK:         qvec.single h %{{.*}} : vector<65x!qco.qubit>
// CHECK-VF64:    qvec.single h %{{.*}} : vector<64x!qco.qubit>
// CHECK-VF64:    qvec.single h %{{.*}} : vector<1x!qco.qubit>

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
