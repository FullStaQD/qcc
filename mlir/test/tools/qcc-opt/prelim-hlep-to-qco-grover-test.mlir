// RUN: qcc-opt %s --inline --prelim-hlep-normalize-lin --prelim-hlep-to-qco --canonicalize | FileCheck %s

// End-to-end lowering of the Grover program from
// prelim-hlep-advanced-test.mlir. Compared to that file, the helpers are
// private and `@main` is haloed, so the inliner (which refuses to inline
// haloed callees into non-haloed functions) can flatten the whole program
// into `@main` before the normalization runs; the inliner's canonicalization
// also folds the `func.call_indirect` on the oracle function value into a
// direct call to `@is_ten`, which then inlines into the phase-tag body.


func.func private @zero_state(%_ : !prelimhlep.unit) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %out_qubit = prelimhlep.lin (
    ) -> (!prelimhlep.lin<i1>) {
        %zero = arith.constant 0 : i1
        prelimhlep.output (%zero : i1)
    }
    return %out_qubit : !prelimhlep.lin<i1>
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
    %out_bit_x = scf.if %in_bit -> !prelimhlep.lin<!prelimhlep.x<1>> {
      %plus = prelimhlep.constant "+" : !prelimhlep.lin<!prelimhlep.x<1>>
      scf.yield %plus : !prelimhlep.lin<!prelimhlep.x<1>>
    } else {
      %minus = prelimhlep.constant "-" : !prelimhlep.lin<!prelimhlep.x<1>>
      scf.yield %minus : !prelimhlep.lin<!prelimhlep.x<1>>
    }
    prelimhlep.output () carrying (%out_bit_x : !prelimhlep.lin<!prelimhlep.x<1>>)
  }
  %out_qubit = prelimhlep.base_change %out_qubit_x_basis : !prelimhlep.lin<!prelimhlep.x<1>> -> !prelimhlep.lin<i1>
  return %out_qubit : !prelimhlep.lin<i1>
}


// Bit-fiddle four separate qubits into an integer representation
func.func private @combine_4(%q_0 : !prelimhlep.lin<i1>, %q_1 : !prelimhlep.lin<i1>, %q_2 : !prelimhlep.lin<i1>, %q_3 : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %qubit_list = prelimhlep.lin (
       %bit_0 : i1 from %q_0 : !prelimhlep.lin<i1>,
       %bit_1 : i1 from %q_1 : !prelimhlep.lin<i1>,
       %bit_2 : i1 from %q_2 : !prelimhlep.lin<i1>,
       %bit_3 : i1 from %q_3 : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i4>) {
        %c1 = arith.constant 1 : i4
        %c2 = arith.constant 2 : i4
        %c3 = arith.constant 3 : i4
        %bit_0_ext = arith.extui %bit_0 : i1 to i4
        %bit_1_ext = arith.extui %bit_1 : i1 to i4
        %bit_2_ext = arith.extui %bit_2 : i1 to i4
        %bit_3_ext = arith.extui %bit_3 : i1 to i4
        %bit_1_shifted = arith.shli %bit_1_ext, %c1 : i4
        %bit_2_shifted = arith.shli %bit_2_ext, %c2 : i4
        %bit_3_shifted = arith.shli %bit_3_ext, %c3 : i4
        %int_01 = arith.ori %bit_0_ext, %bit_1_shifted : i4
        %int_012 = arith.ori %int_01, %bit_2_shifted : i4
        %int_0123 = arith.ori %int_012, %bit_3_shifted : i4
        prelimhlep.output (%int_0123 : i4)
    }
    return %qubit_list : !prelimhlep.lin<i4>
}


// Inverse of @combine_4: bit-fiddle an integer representation apart into four separate qubits
func.func private @split_4(%qubit_list : !prelimhlep.lin<i4>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo = #prelimhlep.halo } {
    %q_0, %q_1, %q_2, %q_3 = prelimhlep.lin (
        %bits : i4 from %qubit_list : !prelimhlep.lin<i4>
    ) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %c1 = arith.constant 1 : i4
        %c2 = arith.constant 2 : i4
        %c3 = arith.constant 3 : i4
        %bit_0 = arith.trunci %bits : i4 to i1
        %bits_1 = arith.shrui %bits, %c1 : i4
        %bit_1 = arith.trunci %bits_1 : i4 to i1
        %bits_2 = arith.shrui %bits, %c2 : i4
        %bit_2 = arith.trunci %bits_2 : i4 to i1
        %bits_3 = arith.shrui %bits, %c3 : i4
        %bit_3 = arith.trunci %bits_3 : i4 to i1
        prelimhlep.output (%bit_0 : i1, %bit_1 : i1, %bit_2 : i1, %bit_3 : i1)
    }
    return %q_0, %q_1, %q_2, %q_3 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}


func.func private @uniform_superposition_4(%_ : !prelimhlep.unit) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
    // TODO: Use a loop to generate the qubits once possible

    %zero_0 = func.call @zero_state(%_) : (!prelimhlep.unit) -> !prelimhlep.lin<i1>
    %zero_1 = func.call @zero_state(%_) : (!prelimhlep.unit) -> !prelimhlep.lin<i1>
    %zero_2 = func.call @zero_state(%_) : (!prelimhlep.unit) -> !prelimhlep.lin<i1>
    %zero_3 = func.call @zero_state(%_) : (!prelimhlep.unit) -> !prelimhlep.lin<i1>

    %h_0 = func.call @hadamard(%zero_0) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    %h_1 = func.call @hadamard(%zero_1) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    %h_2 = func.call @hadamard(%zero_2) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    %h_3 = func.call @hadamard(%zero_3) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>

    %qubit_list = func.call @combine_4(%h_0, %h_1, %h_2, %h_3) : (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i4>
    return %qubit_list : !prelimhlep.lin<i4>
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
    %q_0, %q_1, %q_2, %q_3 = func.call @split_4(%state) : (!prelimhlep.lin<i4>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>)
    %h_0 = func.call @hadamard(%q_0) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    %h_1 = func.call @hadamard(%q_1) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    %h_2 = func.call @hadamard(%q_2) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    %h_3 = func.call @hadamard(%q_3) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    %out_state = func.call @combine_4(%h_0, %h_1, %h_2, %h_3) : (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i4>
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
    // TODO: Use a loop for the iterations once possible

    %_ = prelimhlep.unit_value : !prelimhlep.unit
    %superposition = func.call @uniform_superposition_4(%_) : (!prelimhlep.unit) -> !prelimhlep.lin<i4>

    %tagged_0 = func.call @phase_tag_4(%superposition, %oracle) : (!prelimhlep.lin<i4>, (i4) -> i1) -> !prelimhlep.lin<i4>
    %state_0 = func.call @diffusion_4(%tagged_0) : (!prelimhlep.lin<i4>) -> !prelimhlep.lin<i4>

    %tagged_1 = func.call @phase_tag_4(%state_0, %oracle) : (!prelimhlep.lin<i4>, (i4) -> i1) -> !prelimhlep.lin<i4>
    %state_1 = func.call @diffusion_4(%tagged_1) : (!prelimhlep.lin<i4>) -> !prelimhlep.lin<i4>

    %tagged_2 = func.call @phase_tag_4(%state_1, %oracle) : (!prelimhlep.lin<i4>, (i4) -> i1) -> !prelimhlep.lin<i4>
    %state_2 = func.call @diffusion_4(%tagged_2) : (!prelimhlep.lin<i4>) -> !prelimhlep.lin<i4>

    %result = func.call @measure_4(%state_2) : (!prelimhlep.lin<i4>) -> i4
    return %result : i4
}


// A classical oracle marking the single element 10 = 0b1010
func.func private @is_ten(%x : i4) -> i1 {
    %ten = arith.constant 10 : i4
    %is_ten = arith.cmpi eq, %x, %ten : i4
    return %is_ten : i1
}


// Classical entry point: search for the element marked by @is_ten.
// The measured result is 10 with probability ~0.958.
func.func @main(%u : !prelimhlep.unit) -> i4 attributes { prelimhlep.halo } {
    %oracle = func.constant @is_ten : (i4) -> i1
    %found = func.call @grover_4(%oracle) : ((i4) -> i1) -> i4
    return %found : i4
}


// The whole program flattens into a single QCO circuit over four qubits:
// state preparation, three Grover iterations of a phase tag on 10 = 0b1010
// (X-conjugation on the polarity-0 controls, qubits 0 and 2) alternating
// with the diffusion phase tag on 0b0000 (X-conjugation on all four), and
// a final measurement of all four qubits.

// CHECK-LABEL: func.func @main() -> i4

// State preparation.
// CHECK-COUNT-4: qco.alloc

// Three phase-tag/diffusion iterations, each pair lowered to a controlled Z.
// CHECK: qco.ctrl
// CHECK-NEXT: qco.z
// CHECK-NEXT: qco.yield
// CHECK: qco.ctrl
// CHECK-NEXT: qco.z
// CHECK-NEXT: qco.yield
// CHECK: qco.ctrl
// CHECK-NEXT: qco.z
// CHECK-NEXT: qco.yield
// CHECK: qco.ctrl
// CHECK-NEXT: qco.z
// CHECK-NEXT: qco.yield
// CHECK: qco.ctrl
// CHECK-NEXT: qco.z
// CHECK-NEXT: qco.yield
// CHECK: qco.ctrl
// CHECK-NEXT: qco.z
// CHECK-NEXT: qco.yield

// Final measurement of all four qubits (each sunk right after being
// measured) and recombination into an i4.
// CHECK-COUNT-4: qco.measure{{.*}}{{[[:space:]]+}}qco.sink
// CHECK: arith.ori
// CHECK: return {{.*}} : i4

// CHECK-NOT: prelimhlep
