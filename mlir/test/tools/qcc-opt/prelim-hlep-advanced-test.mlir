// RUN: qcc-opt %s | FileCheck %s


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
