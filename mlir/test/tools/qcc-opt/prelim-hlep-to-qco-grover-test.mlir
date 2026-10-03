// RUN: qcc-opt %s --pass-pipeline='builtin.module(inline,func.func(tmp-raise-scf-to-affine,affine-loop-unroll{unroll-factor=-1 unroll-full-threshold=1000},affine-loop-unroll{unroll-factor=-1 unroll-num-reps=10}),canonicalize,prelim-hlep-lin-to-gates,prelim-hlep-to-qco,canonicalize)' | FileCheck %s
// Merging `lin` ops first and peeling the merged bodies apart again yields
// the same circuit.
// RUN: qcc-opt %s --pass-pipeline='builtin.module(inline,func.func(tmp-raise-scf-to-affine,affine-loop-unroll{unroll-factor=-1 unroll-full-threshold=1000},affine-loop-unroll{unroll-factor=-1 unroll-num-reps=10}),canonicalize,prelim-hlep-merge-lin,prelim-hlep-lin-to-gates,prelim-hlep-to-qco,canonicalize)' | FileCheck %s

// End-to-end lowering of the Grover program from
// prelim-hlep-advanced-test.mlir. Compared to that file, the helpers are
// private and `@main` is haloed, so the inliner (which refuses to inline
// haloed callees into non-haloed functions) can flatten the whole program
// into `@main` before the gates are peeled out; the inliner's canonicalization
// also folds the `func.call_indirect` on the oracle function value into a
// direct call to `@is_ten`, which then inlines into the phase-tag body.
//
// The loops over the qubits and over the Grover iterations are unrolled with
// the same steps as in the qrisp pipeline (see `addLoweringQrisp` in
// Compiler.cpp): `scf.for` is raised to `affine.for`, which is then unrolled
// fully, outer loops included. Afterwards, all qubit indices are constants.


func.func private @zero_register_4(%_ : !prelimhlep.unit) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %out_register = prelimhlep.lin (
    ) -> (!prelimhlep.lin<i4>) {
        %zero = arith.constant 0 : i4
        prelimhlep.output (%zero : i4)
    }
    return %out_register : !prelimhlep.lin<i4>
}


func.func private @x_gate(%qubit: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %out_qubit = prelimhlep.lin (
        %b : i1 from %qubit : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant 1 : i1
        %out_b = arith.xori %b, %one : i1
        prelimhlep.output (%out_b : i1)
    }
    return %out_qubit : !prelimhlep.lin<i1>
}


func.func private @cnot(%control_qubit : !prelimhlep.lin<i1>, %target_qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo = #prelimhlep.halo } {
    %out_control_qubit, %out_target_qubit = prelimhlep.lin (
        %control_bit: i1 from %control_qubit: !prelimhlep.lin<i1>
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


func.func private @hadamard(%in_qubit: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
  %out_qubit_x_basis = prelimhlep.lin (
    %in_bit: i1 from %in_qubit: !prelimhlep.lin<i1>
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


// Take qubit %i out of a register: the partial linearization of the classical
// bijection (x, i) |-> (x without bit i, bit i), with the index captured.
func.func private @extract_4(%register : !prelimhlep.lin<i4>, %i : index) -> (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo = #prelimhlep.halo } {
    %rest, %qubit = prelimhlep.lin (
        %bits : i4 from %register : !prelimhlep.lin<i4>
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


// Inverse of @extract_4: put a qubit back into a register at index %i
func.func private @insert_4(%rest : !prelimhlep.lin<i3>, %qubit : !prelimhlep.lin<i1>, %i : index) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %register = prelimhlep.lin (
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
    return %register : !prelimhlep.lin<i4>
}


func.func private @uniform_superposition_4(%_ : !prelimhlep.unit) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %zero = func.call @zero_register_4(%_) : (!prelimhlep.unit) -> !prelimhlep.lin<i4>
    %superposition = func.call @hadamard_4(%zero) : (!prelimhlep.lin<i4>) -> !prelimhlep.lin<i4>
    return %superposition : !prelimhlep.lin<i4>
}


// Flip the phase of exactly those basis states the oracle marks
func.func private @phase_tag_4(%state : !prelimhlep.lin<i4>, %oracle: (i4) -> i1) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %out_oracle = prelimhlep.lin (
        %bits: i4 from %state : !prelimhlep.lin<i4>
    ) -> (!prelimhlep.lin<i4>) {
        %phase_bit = func.call_indirect %oracle(%bits) : (i4) -> i1
        %phase_tagged_bits = scf.if %phase_bit -> i4 {
            %neg_one = complex.constant [-1.0, 0.0] : complex<f64>
            %inverted_bits = prelimhlep.scale %neg_one, %bits : (complex<f64>, i4) -> i4
            scf.yield %inverted_bits : i4
        } else {
            scf.yield %bits : i4
        }
        prelimhlep.output (%phase_tagged_bits : i4)
    }
    return %out_oracle : !prelimhlep.lin<i4>
}


func.func private @hadamard_4(%state : !prelimhlep.lin<i4>) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    %out_state = scf.for %i = %c0 to %c4 step %c1 iter_args(%register = %state) -> (!prelimhlep.lin<i4>) {
        %rest, %qubit = func.call @extract_4(%register, %i) : (!prelimhlep.lin<i4>, index) -> (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>)
        %h = func.call @hadamard(%qubit) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
        %next_register = func.call @insert_4(%rest, %h, %i) : (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>, index) -> !prelimhlep.lin<i4>
        scf.yield %next_register : !prelimhlep.lin<i4>
    }
    return %out_state : !prelimhlep.lin<i4>
}


// Inversion about the mean: H^4 (2|0><0| - 1) H^4, up to global phase.
// The middle factor is the phase tag of the |0000> basis state.
func.func private @diffusion_4(%state : !prelimhlep.lin<i4>) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %x_basis_state = func.call @hadamard_4(%state) : (!prelimhlep.lin<i4>) -> !prelimhlep.lin<i4>
    %tagged_state = prelimhlep.lin (
        %bits : i4 from %x_basis_state : !prelimhlep.lin<i4>
    ) -> (!prelimhlep.lin<i4>) {
        %zero = arith.constant 0 : i4
        %is_zero = arith.cmpi eq, %bits, %zero : i4
        %tagged_bits = scf.if %is_zero -> i4 {
            %neg_one = complex.constant [-1.0, 0.0] : complex<f64>
            %inverted_bits = prelimhlep.scale %neg_one, %bits : (complex<f64>, i4) -> i4
            scf.yield %inverted_bits : i4
        } else {
            scf.yield %bits : i4
        }
        prelimhlep.output (%tagged_bits : i4)
    }
    %out_state = func.call @hadamard_4(%tagged_state) : (!prelimhlep.lin<i4>) -> !prelimhlep.lin<i4>
    return %out_state : !prelimhlep.lin<i4>
}


// Measure all four qubits at once
func.func private @measure_4(%state : !prelimhlep.lin<i4>) -> i4 attributes { prelimhlep.halo = #prelimhlep.halo } {
    %result = prelimhlep.lin (
        %bits : i4 from %state : !prelimhlep.lin<i4>
    ) -> (i4) {
        prelimhlep.output () carrying (%bits : i4)
    }
    return %result : i4
}


// Full Grover search on four qubits: prepare the uniform superposition, then
// alternate oracle phase tags with inversions about the mean for the optimal
// round(pi/4 * sqrt(16)) = 3 iterations, and measure.
func.func private @grover_4(%oracle : (i4) -> i1) -> i4 attributes { prelimhlep.halo = #prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c3 = arith.constant 3 : index

    %_ = prelimhlep.unit_value : !prelimhlep.unit
    %superposition = func.call @uniform_superposition_4(%_) : (!prelimhlep.unit) -> !prelimhlep.lin<i4>

    %final_state = scf.for %iteration = %c0 to %c3 step %c1 iter_args(%state = %superposition) -> (!prelimhlep.lin<i4>) {
        %tagged = func.call @phase_tag_4(%state, %oracle) : (!prelimhlep.lin<i4>, (i4) -> i1) -> !prelimhlep.lin<i4>
        %next_state = func.call @diffusion_4(%tagged) : (!prelimhlep.lin<i4>) -> !prelimhlep.lin<i4>
        scf.yield %next_state : !prelimhlep.lin<i4>
    }

    %result = func.call @measure_4(%final_state) : (!prelimhlep.lin<i4>) -> i4
    return %result : i4
}


// A classical oracle marking the single element 10 = 0b1010
func.func private @is_ten(%x : i4) -> i1 {
    %ten = arith.constant 10 : i4
    %is_ten = arith.cmpi eq, %x, %ten : i4
    return %is_ten : i1
}


// Classical entry point: search for the element marked by @is_ten.
// The measured result is 10 with probability sin^2(7 asin(1/4)) ~ 0.961.
func.func @main(%u : !prelimhlep.unit) -> i4 attributes { prelimhlep.halo } {
    %oracle = func.constant @is_ten : (i4) -> i1
    %found = func.call @grover_4(%oracle) : ((i4) -> i1) -> i4
    return %found : i4
}


// The whole program flattens into a single QCO circuit over four qubits:
// state preparation, three Grover iterations of a phase tag on 10 = 0b1010
// (X-conjugation on the polarity-0 controls, qubits 0 and 2) alternating
// with the diffusion (X-conjugation on all four around a phase tag on
// 0b0000, between two layers of Hadamards), and a final measurement of all
// four qubits.

// CHECK-LABEL: func.func @main() -> i4

// State preparation: four qubits in |0>, each with a Hadamard. The two RUN
// lines interleave the allocations and the Hadamards differently.
// CHECK-DAG:     qco.alloc
// CHECK-DAG:     qco.alloc
// CHECK-DAG:     qco.alloc
// CHECK-DAG:     qco.alloc
// CHECK-DAG:     qco.h
// CHECK-DAG:     qco.h
// CHECK-DAG:     qco.h
// CHECK-DAG:     qco.h

// Oracle: phase tag on 10 = 0b1010, X-conjugated on qubits 0 and 2.
// CHECK-COUNT-2: qco.x
// CHECK-NOT:     qco.{{[hx]}} %
// CHECK:         qco.ctrl
// CHECK-NEXT:    qco.z
// CHECK-NEXT:    qco.yield
// CHECK-COUNT-2: qco.x
// Diffusion: H^4, phase tag on 0b0000 (X-conjugated on all four), H^4.
// CHECK-COUNT-4: qco.h
// CHECK-COUNT-4: qco.x
// CHECK-NOT:     qco.{{[hx]}} %
// CHECK:         qco.ctrl
// CHECK-NEXT:    qco.z
// CHECK-NEXT:    qco.yield
// CHECK-COUNT-4: qco.x
// CHECK-COUNT-4: qco.h

// Oracle: phase tag on 10 = 0b1010, X-conjugated on qubits 0 and 2.
// CHECK-COUNT-2: qco.x
// CHECK-NOT:     qco.{{[hx]}} %
// CHECK:         qco.ctrl
// CHECK-NEXT:    qco.z
// CHECK-NEXT:    qco.yield
// CHECK-COUNT-2: qco.x
// Diffusion: H^4, phase tag on 0b0000 (X-conjugated on all four), H^4.
// CHECK-COUNT-4: qco.h
// CHECK-COUNT-4: qco.x
// CHECK-NOT:     qco.{{[hx]}} %
// CHECK:         qco.ctrl
// CHECK-NEXT:    qco.z
// CHECK-NEXT:    qco.yield
// CHECK-COUNT-4: qco.x
// CHECK-COUNT-4: qco.h

// Oracle: phase tag on 10 = 0b1010, X-conjugated on qubits 0 and 2.
// CHECK-COUNT-2: qco.x
// CHECK-NOT:     qco.{{[hx]}} %
// CHECK:         qco.ctrl
// CHECK-NEXT:    qco.z
// CHECK-NEXT:    qco.yield
// CHECK-COUNT-2: qco.x
// Diffusion: H^4, phase tag on 0b0000 (X-conjugated on all four), H^4.
// CHECK-COUNT-4: qco.h
// CHECK-COUNT-4: qco.x
// CHECK-NOT:     qco.{{[hx]}} %
// CHECK:         qco.ctrl
// CHECK-NEXT:    qco.z
// CHECK-NEXT:    qco.yield
// CHECK-COUNT-4: qco.x
// CHECK-COUNT-4: qco.h

// Final measurement of all four qubits (each sunk right after being
// measured) and recombination into an i4.
// CHECK-NOT:     qco.{{[hxz]}} %
// CHECK-COUNT-4: qco.measure{{.*}}{{[[:space:]]+}}qco.sink
// CHECK: arith.ori
// CHECK: return {{.*}} : i4

// CHECK-NOT: prelimhlep
