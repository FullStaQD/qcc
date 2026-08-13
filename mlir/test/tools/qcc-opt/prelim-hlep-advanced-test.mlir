// RUN: qcc-opt %s | FileCheck %s


func.func @zero_state(%_ : !prelimhlep.unit) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %out_qubit = prelimhlep.lin (
    ) -> (!prelimhlep.lin<i1>) {
        %zero = arith.constant 0 : i1
        prelimhlep.output (%zero : i1)
    }
    return %out_qubit : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @zero_state

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

// CHECK-LABEL: func.func @hadamard

func.func @uniform_superposition_4(%_ : !prelimhlep.unit) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
    // TODO: Use a loop to generate the qubits once possible

    %zero_0 = func.call @zero_state(%_) : (!prelimhlep.unit) -> !prelimhlep.lin<i1>
    %zero_1 = func.call @zero_state(%_) : (!prelimhlep.unit) -> !prelimhlep.lin<i1>
    %zero_2 = func.call @zero_state(%_) : (!prelimhlep.unit) -> !prelimhlep.lin<i1>
    %zero_3 = func.call @zero_state(%_) : (!prelimhlep.unit) -> !prelimhlep.lin<i1>

    %h_0 = func.call @hadamard(%zero_0) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    %h_1 = func.call @hadamard(%zero_1) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    %h_2 = func.call @hadamard(%zero_2) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    %h_3 = func.call @hadamard(%zero_3) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>

    // Bit-fiddle the qubits into an integer representation
    %qubit_list = prelimhlep.lin (
       %bit_0 : i1 from %h_0 : !prelimhlep.lin<i1>,
       %bit_1 : i1 from %h_1 : !prelimhlep.lin<i1>,
       %bit_2 : i1 from %h_2 : !prelimhlep.lin<i1>,
       %bit_3 : i1 from %h_3 : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i4>) {
        %start_int = arith.constant 0 : i4
        %one = arith.constant 1 : i4
        %bit_0_ext = arith.extui %bit_0 : i1 to i4
        %int_0 = arith.addi %start_int, %bit_0_ext : i4
        %bit_1_ext = arith.extui %bit_1 : i1 to i4
        %int_1 = arith.addi %int_0, %bit_1_ext : i4
        %bit_2_ext = arith.extui %bit_2 : i1 to i4
        %int_2 = arith.addi %int_1, %bit_2_ext : i4
        %bit_3_ext = arith.extui %bit_3 : i1 to i4
        %int_3 = arith.addi %int_2, %bit_3_ext : i4
        prelimhlep.output (%int_3 : i4)
    }
    return %qubit_list : !prelimhlep.lin<i4>
}

// CHECK-LABEL: func.func @uniform_superposition_4

func.func @phase_tag_4(%oracle: (i4) -> i1) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %_ = prelimhlep.unit_value : !prelimhlep.unit
    %uniform_superposition = func.call @uniform_superposition_4(%_) : (!prelimhlep.unit) -> !prelimhlep.lin<i4>
    %out_oracle = prelimhlep.lin (
        %uniform_bits: i4 from %uniform_superposition : !prelimhlep.lin<i4>
    ) -> (!prelimhlep.lin<i4>) {
        %phase_bit = func.call_indirect %oracle(%uniform_bits) : (i4) -> i1
        %phase_tagged_bits = scf.if %phase_bit -> i4 {
            %neg_one = complex.constant [-1.0, 0.0] : complex<f64>
            %inverted_bits = prelimhlep.scale %neg_one, %uniform_bits : (complex<f64>, i4) -> i4
            scf.yield %inverted_bits : i4
        } else {
            scf.yield %uniform_bits : i4
        }
        prelimhlep.output (%phase_tagged_bits : i4)
    }
    return %out_oracle : !prelimhlep.lin<i4>
}

// CHECK-LABEL: func.func @phase_tag_4
