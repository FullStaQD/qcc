// RUN: qcc-opt %s -qvec-merge --split-input-file | FileCheck %s

// CHECK-LABEL: func.func @example_1
func.func @example_1() {
    %q0, %q1, %q2 = qcc.static [0, 1, 2] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qcc.qubit>
    %v2 = vector.from_elements %q2 : vector<1x!qcc.qubit>

    %h0 = qvec.single h %v0 : vector<1x!qcc.qubit>
    %h1 = qvec.single h %v1 : vector<1x!qcc.qubit>
    %h2 = qvec.single h %v2 : vector<1x!qcc.qubit>

    func.return
}

// CHECK:         %[[Q:.*]]:3 = qcc.static [0, 1, 2] : !qcc.qubit
// CHECK:         %[[V0:.*]] = vector.from_elements %[[Q]]#0, %[[Q]]#1, %[[Q]]#2 : vector<3x!qcc.qubit>
// CHECK:         qvec.single h %[[V0]] : vector<3x!qcc.qubit>
// CHECK-NOT:     qvec.

// -----

// CHECK-LABEL: func.func @example_2
func.func @example_2() {
    %q0, %q1, %q2, %q3 = qcc.static [0, 1, 2, 3] : !qcc.qubit

    // h(0) cx(0; 1)
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %h0 = qvec.single h %v0 : vector<1x!qcc.qubit>
    %t0 = vector.from_elements %q1 : vector<1x!qcc.qubit>
    %c0, %d0 = qvec.pair cx %h0, %t0 : vector<1x!qcc.qubit>

    // h(2) cx(2; 3)
    %v1 = vector.from_elements %q2 : vector<1x!qcc.qubit>
    %h1 = qvec.single h %v1 : vector<1x!qcc.qubit>
    %t1 = vector.from_elements %q3 : vector<1x!qcc.qubit>
    %c1, %d1 = qvec.pair cx %h1, %t1 : vector<1x!qcc.qubit>

    func.return
}

// CHECK:         %[[Q:.*]]:4 = qcc.static [0, 1, 2, 3] : !qcc.qubit

// h(0, 2) cx(0, 2; 1, 3)
// CHECK:         %[[C0:.*]] = vector.from_elements %[[Q]]#0, %[[Q]]#2 : vector<2x!qcc.qubit>
// CHECK:         %[[C1:.*]] = qvec.single h %[[C0]] : vector<2x!qcc.qubit>
// CHECK:         %[[T0:.*]] = vector.from_elements %[[Q]]#1, %[[Q]]#3 : vector<2x!qcc.qubit>
// CHECK:                    = qvec.pair cx %[[C1]], %[[T0]] : vector<2x!qcc.qubit>

// -----

// CHECK-LABEL: func.func @dependent_singles
func.func @dependent_singles() {
    %q0 = qcc.static [0] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>

    %v1 = qvec.single h %v0 : vector<1x!qcc.qubit>
    %v2 = qvec.single h %v1 : vector<1x!qcc.qubit>
    %v3 = qvec.single h %v2 : vector<1x!qcc.qubit>

    func.return
}

// Do not merge!
// CHECK:         %[[V1:.*]] = qvec.single h %{{.*}} : vector<1x!qcc.qubit>
// CHECK:         %[[V2:.*]] = qvec.single h %[[V1]] : vector<1x!qcc.qubit>
// CHECK:                    = qvec.single h %[[V2]] : vector<1x!qcc.qubit>

// -----

// CHECK-LABEL: func.func @dependent_pairs
func.func @dependent_pairs() {
    %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
    %a0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %b0 = vector.from_elements %q1 : vector<1x!qcc.qubit>

    %a1, %b1 = qvec.pair cx %a0, %b0 : vector<1x!qcc.qubit>
    %a2, %b2 = qvec.pair cx %a1, %b1 : vector<1x!qcc.qubit>

    func.return
}

// Do not merge!
// CHECK:         qvec.pair cx %{{.*}}, %{{.*}} : vector<1x!qcc.qubit>
// CHECK:         qvec.pair cx %{{.*}}, %{{.*}} : vector<1x!qcc.qubit>

// -----

// Measurements pack like gates do, and across both operands of the `pair` they follow: all four
// qubits are measured by one instruction.

// CHECK-LABEL: func.func @measurements
func.func @measurements() {
    %q0, %q1, %q2, %q3 = qcc.static [0, 1, 2, 3] : !qcc.qubit
    %a0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %b0 = vector.from_elements %q1 : vector<1x!qcc.qubit>
    %c0 = vector.from_elements %q2 : vector<1x!qcc.qubit>
    %d0 = vector.from_elements %q3 : vector<1x!qcc.qubit>

    %a1, %b1 = qvec.pair cx %a0, %b0 : vector<1x!qcc.qubit>
    %c1, %d1 = qvec.pair cx %c0, %d0 : vector<1x!qcc.qubit>

    %ao, %a2 = qvec.measure z %a1 : vector<1x!qcc.qubit> -> vector<1xi1>
    %bo, %b2 = qvec.measure z %b1 : vector<1x!qcc.qubit> -> vector<1xi1>
    %do, %c2 = qvec.measure z %c1 : vector<1x!qcc.qubit> -> vector<1xi1>
    %eo, %d2 = qvec.measure z %d1 : vector<1x!qcc.qubit> -> vector<1xi1>

    func.return
}

// CHECK:         qvec.pair cx %{{.*}}, %{{.*}} : vector<2x!qcc.qubit>
// CHECK-NOT:     qvec.pair cx
// CHECK-COUNT-4: vector.extract
// CHECK:         %[[V0:.*]] = vector.from_elements
// CHECK:         qvec.measure z %[[V0]] : vector<4x!qcc.qubit> -> vector<4xi1>
// CHECK-NOT:     qvec.measure

// -----

// CHECK-LABEL: func.func @measurement_bits_extracted_for_user
func.func @measurement_bits_extracted_for_user(%k: i1) -> i1 {
    %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
    %a0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %b0 = vector.from_elements %q1 : vector<1x!qcc.qubit>

    %a1, %r0 = qvec.measure z %a0 : vector<1x!qcc.qubit> -> vector<1xi1>
    %r00 = vector.extract %r0[0] : i1 from vector<1xi1>
    %xori = arith.xori %r00, %k : i1

    %b1, %t0 = qvec.measure z %b0 : vector<1x!qcc.qubit> -> vector<1xi1>
    %t00 = vector.extract %t0[0] : i1 from vector<1xi1>
    %andi = arith.andi %xori, %t00 : i1

    func.return %andi : i1
}

// Measure with a single instruction, then extract the bits where they are used.
// CHECK:         %{{.*}}, %[[BITS:.*]] = qvec.measure z %{{.*}} : vector<2x!qcc.qubit> -> vector<2xi1>
// CHECK-DAG:     %[[R0:.*]] = vector.extract %[[BITS]][0] : i1 from vector<2xi1>
// CHECK-DAG:     %[[R1:.*]] = vector.extract %[[BITS]][1] : i1 from vector<2xi1>
// CHECK-DAG:     %[[N:.*]] = arith.xori %[[R0]], %{{.*}} : i1
// CHECK:         arith.andi %[[N]], %[[R1]] : i1

// -----

// Measurements and resets merge per basis, and never with each other.

// CHECK-LABEL: func.func @bases
func.func @bases() {
    %q0, %q1, %q2, %q3, %q4, %q5 = qcc.static [0, 1, 2, 3, 4, 5] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qcc.qubit>
    %v2 = vector.from_elements %q2 : vector<1x!qcc.qubit>
    %v3 = vector.from_elements %q3 : vector<1x!qcc.qubit>
    %v4 = vector.from_elements %q4 : vector<1x!qcc.qubit>
    %v5 = vector.from_elements %q5 : vector<1x!qcc.qubit>

    %a, %bits_a = qvec.measure z %v0 : vector<1x!qcc.qubit> -> vector<1xi1>
    %b, %bits_b = qvec.measure x %v1 : vector<1x!qcc.qubit> -> vector<1xi1>
    %c, %bits_c = qvec.measure z %v2 : vector<1x!qcc.qubit> -> vector<1xi1>
    %d = qvec.reset z %v3 : vector<1x!qcc.qubit>
    %e = qvec.reset x %v4 : vector<1x!qcc.qubit>
    %f = qvec.reset z %v5 : vector<1x!qcc.qubit>

    func.return
}

// CHECK:         qvec.measure z %{{.*}} : vector<2x!qcc.qubit> -> vector<2xi1>
// CHECK:         qvec.measure x %{{.*}} : vector<1x!qcc.qubit> -> vector<1xi1>
// CHECK:         qvec.reset z %{{.*}} : vector<2x!qcc.qubit>
// CHECK:         qvec.reset x %{{.*}} : vector<1x!qcc.qubit>
// CHECK-NOT:     qvec.

// -----

// CHECK-LABEL: func.func @qubits_maybe_not_disjoint
func.func @qubits_maybe_not_disjoint(%qs: vector<2x!qcc.qubit>, %rs: vector<2x!qcc.qubit>) {
    %a = qvec.single h %qs : vector<2x!qcc.qubit>
    %b = qvec.single h %rs : vector<2x!qcc.qubit>
    func.return
}

// We must not merge because we cannot prove the qubits are disjoint:
// CHECK:         qvec.single h %{{.*}} : vector<2x!qcc.qubit>
// CHECK:         qvec.single h %{{.*}} : vector<2x!qcc.qubit>

// -----

func.func private @opaque_gate(!qcc.qubit) -> !qcc.qubit

// CHECK-LABEL: func.func @untraceable_producer
func.func @untraceable_producer() {
    %q0, %q1, %q2 = qcc.static [0, 1, 2] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qcc.qubit>
    %v2 = vector.from_elements %q2 : vector<1x!qcc.qubit>

    %h0 = qvec.single h %v0 : vector<1x!qcc.qubit>
    %h1 = qvec.single h %v1 : vector<1x!qcc.qubit>

    // The relation between %e0 and %o0 is unknown (could even refer to different qubits). The call could also have
    // other (unknown) side effects. Hence the third Hadamard must not be merged with the other ones.
    %e0 = vector.extract %v2[0] : !qcc.qubit from vector<1x!qcc.qubit>
    %o0 = func.call @opaque_gate(%e0) : (!qcc.qubit) -> !qcc.qubit // acts as a barrier here
    %w2 = vector.from_elements %o0 : vector<1x!qcc.qubit>
    %h2 = qvec.single h %w2 : vector<1x!qcc.qubit>

    func.return
}

// The two independent hadamards merge, the one behind the opaque call stays on its own.
// CHECK:         qvec.single h %{{.*}} : vector<2x!qcc.qubit>
// CHECK:         call @opaque_gate
// CHECK:         qvec.single h %{{.*}} : vector<1x!qcc.qubit>
// CHECK-NOT:     qvec.

// -----

// CHECK-LABEL: func.func @wide_member_slice_is_one_op
func.func @wide_member_slice_is_one_op() {
    %q0, %q1, %q2, %q3 = qcc.static [0, 1, 2, 3] : !qcc.qubit
    %a0 = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
    %b0 = vector.from_elements %q2, %q3 : vector<2x!qcc.qubit>

    %a1 = qvec.single h %a0 : vector<2x!qcc.qubit> // layer 0
    %b1 = qvec.single h %b0 : vector<2x!qcc.qubit> // layer 0

    // Different gate kinds, so these two never merge and their operands stay in the IR to be looked at.
    %a2 = qvec.single x %a1 : vector<2x!qcc.qubit> // layer 1
    %b2 = qvec.single y %b1 : vector<2x!qcc.qubit> // layer 1

    func.return
}

// Handing a member its share of the merged result takes one operation, whatever the member's width.
// CHECK:         %[[H:.*]] = qvec.single h %{{.*}} : vector<4x!qcc.qubit>
// CHECK:         %[[S0:.*]] = vector.extract_strided_slice %[[H]] {offsets = [0], sizes = [2], strides = [1]}
// CHECK:         %[[S1:.*]] = vector.extract_strided_slice %[[H]] {offsets = [2], sizes = [2], strides = [1]}
// CHECK:         qvec.single x %[[S0]] : vector<2x!qcc.qubit>
// CHECK:         qvec.single y %[[S1]] : vector<2x!qcc.qubit>

// -----

// CHECK-LABEL: func.func @no_merge_across_if
func.func @no_merge_across_if(%cond: i1) {
    %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qcc.qubit>

    %h1 = qvec.single h %v1 : vector<1x!qcc.qubit>
    %x0 = scf.if %cond -> (vector<1x!qcc.qubit>) {
      %x = qvec.single x %v0 : vector<1x!qcc.qubit>
      scf.yield %x : vector<1x!qcc.qubit>
    } else {
      scf.yield %v0 : vector<1x!qcc.qubit>
    }
    %h0 = qvec.single h %x0 : vector<1x!qcc.qubit>

    func.return
}

// CHECK:         qvec.single h %{{.*}} : vector<1x!qcc.qubit>
// CHECK:         scf.if
// CHECK:           qvec.single x
// CHECK:         }
// CHECK:         qvec.single h %{{.*}} : vector<1x!qcc.qubit>

// -----

// CHECK-LABEL: func.func @merge_behind_ifs
func.func @merge_behind_ifs() {
    %q0, %q1, %q2 = qcc.static [0, 1, 2] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qcc.qubit>
    %v2 = vector.from_elements %q2 : vector<1x!qcc.qubit>

    %h0 = qvec.single h %v0 : vector<1x!qcc.qubit>
    %m2, %bits = qvec.measure z %v2 : vector<1x!qcc.qubit> -> vector<1xi1>
    %cond = vector.extract %bits[0] : i1 from vector<1xi1>

    %a0 = scf.if %cond -> (vector<1x!qcc.qubit>) {
      %x = qvec.single x %h0 : vector<1x!qcc.qubit>
      scf.yield %x : vector<1x!qcc.qubit>
    } else {
      scf.yield %h0 : vector<1x!qcc.qubit>
    }
    %a1 = scf.if %cond -> (vector<1x!qcc.qubit>) {
      %x = qvec.single x %v1 : vector<1x!qcc.qubit>
      scf.yield %x : vector<1x!qcc.qubit>
    } else {
      scf.yield %v1 : vector<1x!qcc.qubit>
    }

    %y0 = qvec.single y %a0 : vector<1x!qcc.qubit>
    %y1 = qvec.single y %a1 : vector<1x!qcc.qubit>

    func.return
}

// CHECK:         %[[A0:.*]] = scf.if %{{.*}} -> (vector<1x!qcc.qubit>)
// CHECK:         %[[A1:.*]] = scf.if %{{.*}} -> (vector<1x!qcc.qubit>)
// CHECK:         %[[E0:.*]] = vector.extract %[[A0]][0]
// CHECK:         %[[E1:.*]] = vector.extract %[[A1]][0]
// CHECK:         %[[V:.*]] = vector.from_elements %[[E0]], %[[E1]] : vector<2x!qcc.qubit>
// CHECK:         qvec.single y %[[V]] : vector<2x!qcc.qubit>
// CHECK-NOT:     qvec.single y

// -----

// `%v` is used twice, so both gates are in layer 0 although they act on the same qubit.

// CHECK-LABEL: func.func @no_merge_on_same_qubit
func.func @no_merge_on_same_qubit() {
    %q0 = qcc.static [0] : !qcc.qubit
    %v = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %h1 = qvec.single h %v : vector<1x!qcc.qubit>
    %h2 = qvec.single h %v : vector<1x!qcc.qubit>
    func.return
}

// CHECK:         qvec.single h %{{.*}} : vector<1x!qcc.qubit>
// CHECK:         qvec.single h %{{.*}} : vector<1x!qcc.qubit>
