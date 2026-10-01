// RUN: qcc-opt %s | FileCheck %s

func.func @zero_register_4(%_ : !prelimhlep.unit) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %out_register = prelimhlep.lin (
    ) -> (!prelimhlep.lin<i4>) {
        %zero = arith.constant 0 : i4
        prelimhlep.output (%zero : i4)
    }
    return %out_register : !prelimhlep.lin<i4>
}

// CHECK-LABEL: func.func @zero_register_4

func.func @x_gate(%qubit: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %out_qubit = prelimhlep.lin (
        %b : i1 from %qubit : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant 1 : i1
        %out_b = arith.xori %b, %one : i1
        prelimhlep.output (%out_b : i1)
    }
    return %out_qubit : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @x_gate

func.func @cnot(%control_qubit : !prelimhlep.lin<i1>, %target_qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo = #prelimhlep.halo } {
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

// CHECK-LABEL: func.func @cnot

func.func @hadamard(%in_qubit: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
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

// CHECK-LABEL: func.func @hadamard

// Take qubit %i out of a register: the partial linearization of the classical
// bijection (x, i) |-> (x without bit i, bit i) in the register and both
// outputs, with the index captured, i.e. classical. Each index yields a single
// world, in which qubit %i is moved to the end. The bit arithmetic is done in
// i64, so that shifting by i + 1 stays below the bit width.
func.func @extract_4(%register : !prelimhlep.lin<i4>, %i : index) -> (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo = #prelimhlep.halo } {
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

// CHECK-LABEL: func.func @extract_4

// Inverse of @extract_4: put a qubit back into a register at index %i
func.func @insert_4(%rest : !prelimhlep.lin<i3>, %qubit : !prelimhlep.lin<i1>, %i : index) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
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

// CHECK-LABEL: func.func @insert_4

func.func @uniform_superposition_4(%_ : !prelimhlep.unit) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %zero = func.call @zero_register_4(%_) : (!prelimhlep.unit) -> !prelimhlep.lin<i4>
    %superposition = func.call @hadamard_4(%zero) : (!prelimhlep.lin<i4>) -> !prelimhlep.lin<i4>
    return %superposition : !prelimhlep.lin<i4>
}

// CHECK-LABEL: func.func @uniform_superposition_4

// Flip the phase of exactly those basis states the oracle marks
func.func @phase_tag_4(%state : !prelimhlep.lin<i4>, %oracle: (i4) -> i1) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
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

// CHECK-LABEL: func.func @phase_tag_4

func.func @hadamard_4(%state : !prelimhlep.lin<i4>) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
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

// CHECK-LABEL: func.func @hadamard_4
// CHECK:         scf.for {{.*}} iter_args({{.*}}) -> (!prelimhlep.lin<i4>)

// Inversion about the mean: H^4 (2|0><0| - 1) H^4, up to global phase.
// The middle factor is the phase tag of the |0000> basis state.
func.func @diffusion_4(%state : !prelimhlep.lin<i4>) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
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

// CHECK-LABEL: func.func @diffusion_4

// Measure all four qubits at once
func.func @measure_4(%state : !prelimhlep.lin<i4>) -> i4 attributes { prelimhlep.halo = #prelimhlep.halo } {
    %result = prelimhlep.lin (
        %bits : i4 from %state : !prelimhlep.lin<i4>
    ) -> (i4) {
        prelimhlep.output () carrying (%bits : i4)
    }
    return %result : i4
}

// CHECK-LABEL: func.func @measure_4

// Full Grover search on four qubits: prepare the uniform superposition, then
// alternate oracle phase tags with inversions about the mean for the optimal
// round(pi/4 * sqrt(16)) = 3 iterations, and measure.
func.func @grover_4(%oracle : (i4) -> i1) -> i4 attributes { prelimhlep.halo = #prelimhlep.halo } {
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

// CHECK-LABEL: func.func @grover_4
// CHECK:         scf.for {{.*}} iter_args({{.*}}) -> (!prelimhlep.lin<i4>)

// A classical oracle marking the single element 10 = 0b1010
func.func @is_ten(%x : i4) -> i1 {
    %ten = arith.constant 10 : i4
    %is_ten = arith.cmpi eq, %x, %ten : i4
    return %is_ten : i1
}

// CHECK-LABEL: func.func @is_ten

// Classical entry point: search for the element marked by @is_ten.
// The measured result is 10 with probability sin^2(7 asin(1/4)) ~ 0.961.
func.func @main() -> i4 {
    %oracle = func.constant @is_ten : (i4) -> i1
    %found = func.call @grover_4(%oracle) : ((i4) -> i1) -> i4
    return %found : i4
}

// CHECK-LABEL: func.func @main
