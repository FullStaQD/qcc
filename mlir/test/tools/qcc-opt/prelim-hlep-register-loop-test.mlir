// RUN: qcc-opt %s | FileCheck %s --check-prefix=ROUNDTRIP
// RUN: qcc-opt %s --pass-pipeline='builtin.module(inline,func.func(tmp-raise-scf-to-affine,affine-loop-unroll{unroll-factor=-1 unroll-full-threshold=1000},affine-loop-unroll{unroll-factor=-1 unroll-num-reps=10}),canonicalize,prelim-hlep-lin-to-gates,canonicalize)' | FileCheck %s

// Loops over the qubits of a register `!prelimhlep.lin<iN>`.
//
// A single qubit is accessed at a dynamic index by partially linearizing the
// classical bijection (x, i) |-> (x without bit i, bit i) in the register and
// both outputs, with the index `i` captured, i.e. classical. Each index yields
// a single world, whose fiber map moves qubit `i` to the end. Linearizing the
// inverse bijection puts the qubit back. The remaining register has the static
// type `!prelimhlep.lin<i(N-1)>`: the position of the gap is classical data
// held by the index, not by the type.
//
// The unrolling steps are the ones of the qrisp pipeline (see
// `addLoweringQrisp` in Compiler.cpp). Once unrolled, all indices are
// constants, and the peeling turns every extract/insert pair into wiring.
//
// The helpers are private, so that the inliner erases them: their bodies
// shift by a dynamic amount, which the peeling cannot lower.

// Lin of (x, i) |-> (x without bit i, bit i). The bit arithmetic is done in
// i64, so that shifting by i + 1 stays below the bit width.
func.func private @extract_4(%reg : !prelimhlep.lin<i4>, %i : index) -> (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %rest, %qubit = prelimhlep.lin (
        %bits : i4 from %reg : !prelimhlep.lin<i4>
    ) -> (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>) {
        %c1 = arith.constant 1 : i64
        %x = arith.extui %bits : i4 to i64
        %s = arith.index_cast %i : index to i64
        %x_shifted = arith.shrui %x, %s : i64
        %bit = arith.trunci %x_shifted : i64 to i1
        %s_next = arith.addi %s, %c1 : i64
        %one_at_s = arith.shli %c1, %s : i64
        %low_mask = arith.subi %one_at_s, %c1 : i64
        %low = arith.andi %x, %low_mask : i64
        %high_shifted = arith.shrui %x, %s_next : i64
        %high = arith.shli %high_shifted, %s : i64
        %rest_wide = arith.ori %low, %high : i64
        %rest_bits = arith.trunci %rest_wide : i64 to i3
        prelimhlep.output (%rest_bits : i3, %bit : i1)
    }
    return %rest, %qubit : !prelimhlep.lin<i3>, !prelimhlep.lin<i1>
}

// Inverse of @extract_4: Lin of (rest, b, i) |-> rest with b inserted at bit i.
func.func private @insert_4(%rest : !prelimhlep.lin<i3>, %qubit : !prelimhlep.lin<i1>, %i : index) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo } {
    %reg = prelimhlep.lin (
        %rest_bits : i3 from %rest : !prelimhlep.lin<i3>,
        %bit : i1 from %qubit : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i4>) {
        %c1 = arith.constant 1 : i64
        %r = arith.extui %rest_bits : i3 to i64
        %b = arith.extui %bit : i1 to i64
        %s = arith.index_cast %i : index to i64
        %s_next = arith.addi %s, %c1 : i64
        %one_at_s = arith.shli %c1, %s : i64
        %low_mask = arith.subi %one_at_s, %c1 : i64
        %low = arith.andi %r, %low_mask : i64
        %high_shifted = arith.shrui %r, %s : i64
        %high = arith.shli %high_shifted, %s_next : i64
        %bit_at_s = arith.shli %b, %s : i64
        %low_high = arith.ori %low, %high : i64
        %x = arith.ori %low_high, %bit_at_s : i64
        %bits = arith.trunci %x : i64 to i4
        prelimhlep.output (%bits : i4)
    }
    return %reg : !prelimhlep.lin<i4>
}

// Same as @extract_4, one qubit less.
func.func private @extract_3(%reg : !prelimhlep.lin<i3>, %i : index) -> (!prelimhlep.lin<i2>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %rest, %qubit = prelimhlep.lin (
        %bits : i3 from %reg : !prelimhlep.lin<i3>
    ) -> (!prelimhlep.lin<i2>, !prelimhlep.lin<i1>) {
        %c1 = arith.constant 1 : i64
        %x = arith.extui %bits : i3 to i64
        %s = arith.index_cast %i : index to i64
        %x_shifted = arith.shrui %x, %s : i64
        %bit = arith.trunci %x_shifted : i64 to i1
        %s_next = arith.addi %s, %c1 : i64
        %one_at_s = arith.shli %c1, %s : i64
        %low_mask = arith.subi %one_at_s, %c1 : i64
        %low = arith.andi %x, %low_mask : i64
        %high_shifted = arith.shrui %x, %s_next : i64
        %high = arith.shli %high_shifted, %s : i64
        %rest_wide = arith.ori %low, %high : i64
        %rest_bits = arith.trunci %rest_wide : i64 to i2
        prelimhlep.output (%rest_bits : i2, %bit : i1)
    }
    return %rest, %qubit : !prelimhlep.lin<i2>, !prelimhlep.lin<i1>
}

// Same as @insert_4, one qubit less.
func.func private @insert_3(%rest : !prelimhlep.lin<i2>, %qubit : !prelimhlep.lin<i1>, %i : index) -> !prelimhlep.lin<i3> attributes { prelimhlep.halo } {
    %reg = prelimhlep.lin (
        %rest_bits : i2 from %rest : !prelimhlep.lin<i2>,
        %bit : i1 from %qubit : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i3>) {
        %c1 = arith.constant 1 : i64
        %r = arith.extui %rest_bits : i2 to i64
        %b = arith.extui %bit : i1 to i64
        %s = arith.index_cast %i : index to i64
        %s_next = arith.addi %s, %c1 : i64
        %one_at_s = arith.shli %c1, %s : i64
        %low_mask = arith.subi %one_at_s, %c1 : i64
        %low = arith.andi %r, %low_mask : i64
        %high_shifted = arith.shrui %r, %s : i64
        %high = arith.shli %high_shifted, %s_next : i64
        %bit_at_s = arith.shli %b, %s : i64
        %low_high = arith.ori %low, %high : i64
        %x = arith.ori %low_high, %bit_at_s : i64
        %bits = arith.trunci %x : i64 to i3
        prelimhlep.output (%bits : i3)
    }
    return %reg : !prelimhlep.lin<i3>
}

func.func private @x_gate(%qubit : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %out_qubit = prelimhlep.lin (
        %b : i1 from %qubit : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant 1 : i1
        %out_b = arith.xori %b, %one : i1
        prelimhlep.output (%out_b : i1)
    }
    return %out_qubit : !prelimhlep.lin<i1>
}

func.func private @cnot(%control_qubit : !prelimhlep.lin<i1>, %target_qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %out_control_qubit, %out_target_qubit = prelimhlep.lin (
        %control_bit : i1 from %control_qubit : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %out_target = scf.if %control_bit -> (!prelimhlep.lin<i1>) {
            %modified_target = func.call @x_gate(%target_qubit) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
            scf.yield %modified_target : !prelimhlep.lin<i1>
        } else {
            scf.yield %target_qubit : !prelimhlep.lin<i1>
        }
        prelimhlep.output (%control_bit : i1) carrying (%out_target : !prelimhlep.lin<i1>)
    }
    return %out_control_qubit, %out_target_qubit : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

func.func private @hadamard(%in_qubit : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %out_qubit_x_basis = prelimhlep.lin (
        %in_bit : i1 from %in_qubit : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<!prelimhlep.x<1>>) {
        %out_bit_x = scf.if %in_bit -> !prelimhlep.x<1> {
            %minus = prelimhlep.constant "-" : !prelimhlep.x<1>
            scf.yield %minus : !prelimhlep.x<1>
        } else {
            %plus = prelimhlep.constant "+" : !prelimhlep.x<1>
            scf.yield %plus : !prelimhlep.x<1>
        }
        prelimhlep.output (%out_bit_x : !prelimhlep.x<1>)
    }
    %out_qubit = prelimhlep.base_change %out_qubit_x_basis : !prelimhlep.lin<!prelimhlep.x<1>> -> !prelimhlep.lin<i1>
    return %out_qubit : !prelimhlep.lin<i1>
}

// A Hadamard on every qubit. The register is the loop-carried value, the
// induction variable is the index.

// ROUNDTRIP-LABEL: func.func @hadamard_all
// ROUNDTRIP:         scf.for {{.*}} iter_args({{.*}}) -> (!prelimhlep.lin<i4>)
// ROUNDTRIP:           func.call @extract_4
// ROUNDTRIP:           func.call @hadamard
// ROUNDTRIP:           func.call @insert_4
// ROUNDTRIP:           scf.yield {{.*}} : !prelimhlep.lin<i4>

// CHECK-LABEL: func.func @hadamard_all
// CHECK-SAME:      (%[[REG:.*]]: !prelimhlep.lin<i4>)
// CHECK-NOT:     affine.for
// CHECK:         %[[Q:.*]]:4 = hlepgate.split %[[REG]] : !prelimhlep.lin<i4>
// CHECK:         hlepgate.single h %[[Q]]#0
// CHECK:         hlepgate.single h %[[Q]]#1
// CHECK:         hlepgate.single h %[[Q]]#2
// CHECK:         hlepgate.single h %[[Q]]#3
// CHECK:         %[[OUT:.*]] = hlepgate.join {{.*}} : !prelimhlep.lin<i4>
// CHECK-NOT:     hlepgate
// CHECK:         return %[[OUT]]
func.func @hadamard_all(%state : !prelimhlep.lin<i4>) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    %out = scf.for %i = %c0 to %c4 step %c1 iter_args(%reg = %state) -> (!prelimhlep.lin<i4>) {
        %rest, %qubit = func.call @extract_4(%reg, %i) : (!prelimhlep.lin<i4>, index) -> (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>)
        %h = func.call @hadamard(%qubit) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
        %next = func.call @insert_4(%rest, %h, %i) : (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>, index) -> !prelimhlep.lin<i4>
        scf.yield %next : !prelimhlep.lin<i4>
    }
    return %out : !prelimhlep.lin<i4>
}

// A CNOT ladder: CNOT(i, i + 1) for i = 0, 1, 2. Two qubits are accessed by
// extracting twice. The second index refers to the register that remains
// after the first extraction, so qubit i + 1 is at index i there. Aliasing
// cannot be expressed: the two qubits are always distinct.

// CHECK-LABEL: func.func @cnot_ladder
// CHECK-SAME:      (%[[REG:.*]]: !prelimhlep.lin<i4>)
// CHECK-NOT:     affine.for
// CHECK:         %[[Q:.*]]:4 = hlepgate.split %[[REG]] : !prelimhlep.lin<i4>
// CHECK:         %[[C0:.*]], %[[T0:.*]] = hlepgate.single x %[[Q]]#1 ctrl(%[[Q]]#0)
// CHECK:         %[[C1:.*]], %[[T1:.*]] = hlepgate.single x %[[Q]]#2 ctrl(%[[T0]])
// CHECK:         %[[C2:.*]], %[[T2:.*]] = hlepgate.single x %[[Q]]#3 ctrl(%[[T1]])
// CHECK:         %[[OUT:.*]] = hlepgate.join %[[C0]], %[[C1]], %[[C2]], %[[T2]] : !prelimhlep.lin<i4>
// CHECK:         return %[[OUT]]
func.func @cnot_ladder(%state : !prelimhlep.lin<i4>) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c3 = arith.constant 3 : index
    %out = scf.for %i = %c0 to %c3 step %c1 iter_args(%reg = %state) -> (!prelimhlep.lin<i4>) {
        %rest_3, %control = func.call @extract_4(%reg, %i) : (!prelimhlep.lin<i4>, index) -> (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>)
        %rest_2, %target = func.call @extract_3(%rest_3, %i) : (!prelimhlep.lin<i3>, index) -> (!prelimhlep.lin<i2>, !prelimhlep.lin<i1>)
        %out_control, %out_target = func.call @cnot(%control, %target) : (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>)
        %next_3 = func.call @insert_3(%rest_2, %out_target, %i) : (!prelimhlep.lin<i2>, !prelimhlep.lin<i1>, index) -> !prelimhlep.lin<i3>
        %next = func.call @insert_4(%next_3, %out_control, %i) : (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>, index) -> !prelimhlep.lin<i4>
        scf.yield %next : !prelimhlep.lin<i4>
    }
    return %out : !prelimhlep.lin<i4>
}

// Nested loops: two rounds of a Hadamard on every qubit followed by an X on
// qubit 1 (at a constant index). The inner loop comes from inlining
// @hadamard_all; both levels are unrolled.

// CHECK-LABEL: func.func @nested
// CHECK-SAME:      (%[[REG:.*]]: !prelimhlep.lin<i4>)
// CHECK-NOT:     affine.for
// CHECK:         %[[Q:.*]]:4 = hlepgate.split %[[REG]] : !prelimhlep.lin<i4>
// CHECK-COUNT-4: hlepgate.single h
// CHECK:         hlepgate.single x
// CHECK-COUNT-4: hlepgate.single h
// CHECK:         hlepgate.single x
// CHECK:         %[[OUT:.*]] = hlepgate.join {{.*}} : !prelimhlep.lin<i4>
// CHECK-NOT:     hlepgate
// CHECK:         return %[[OUT]]
func.func @nested(%state : !prelimhlep.lin<i4>) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c2 = arith.constant 2 : index
    %out = scf.for %k = %c0 to %c2 step %c1 iter_args(%reg = %state) -> (!prelimhlep.lin<i4>) {
        %h = func.call @hadamard_all(%reg) : (!prelimhlep.lin<i4>) -> !prelimhlep.lin<i4>
        %rest, %qubit = func.call @extract_4(%h, %c1) : (!prelimhlep.lin<i4>, index) -> (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>)
        %x = func.call @x_gate(%qubit) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
        %next = func.call @insert_4(%rest, %x, %c1) : (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>, index) -> !prelimhlep.lin<i4>
        scf.yield %next : !prelimhlep.lin<i4>
    }
    return %out : !prelimhlep.lin<i4>
}
