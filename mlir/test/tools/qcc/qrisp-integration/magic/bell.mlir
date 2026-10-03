// RUN: qcc %s --quantum-device=magic --device-description=%S/Inputs/device-2x3.mlir --compile-to=mlir | FileCheck %s --check-prefix=CHECK-MLIR
// RUN: qcc %s --quantum-device=magic --device-description=%S/Inputs/device-2x3.mlir --compile-to=custom-magic -o %t.txt
// RUN: FileCheck %s --check-prefix=CHECK-TXT < %t.txt
// RUN: %if magic-runner %{ magic-runner --file %t.txt --device %S/Inputs/device-2x3.mlir -s 5 | FileCheck %s --check-prefix=CHECK-SIM %}

// GENERATED FROM QRISP VERSION 0.9.6

builtin.module @jasp_module {
  func.func public @main(%arg0: !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState) {
    %0 = arith.constant dense<2> : tensor<i64>
    %1, %2 = "jasp.create_qubits"(%0, %arg0) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %3 = arith.constant dense<0> : tensor<i64>
    %4 = "jasp.get_qubit"(%1, %3) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %5 = "jasp.quantum_gate"(%4, %2) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %6 = arith.constant dense<1> : tensor<i64>
    %7 = "jasp.get_qubit"(%1, %6) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %8 = "jasp.quantum_gate"(%4, %7, %5) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %9, %10 = "jasp.measure"(%1, %8) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
    func.return %9, %10 : tensor<i64>, !jasp.QuantumState
  }
}

// Both ions fit into trap 0, so trap 1 stays empty and nothing is shuttled. Only native ops remain.
// CHECK-MLIR:      !chain = !magic.ion_chain<0, [0:1, 1:1]>
// CHECK-MLIR:      func.func public @main() attributes {qcc.entry_point}
// CHECK-MLIR-NEXT:   %[[C0:.*]] = magic.init : !chain
// CHECK-MLIR-NEXT:   %[[C1:.*]] = magic.sym_zxz %[[C0]] ions [0, 1]
// CHECK-MLIR-NEXT:   %[[C2:.*]] = magic.delay %[[C1]] {ticks = {{[0-9]+}} : i64} : !chain
// CHECK-MLIR-NEXT:   %[[C3:.*]] = magic.sym_zxz %[[C2]] ions [1]
// CHECK-MLIR-NEXT:   %[[M:.*]]:2 = magic.mzd %[[C3]] : !chain -> i1, i1
// CHECK-MLIR-NEXT:   aux.record_int %[[M]]#0 : i1
// CHECK-MLIR-NEXT:   aux.record_int %[[M]]#1 : i1
// CHECK-MLIR-NEXT:   return

// CHECK-TXT:      OPENQASM 3.0;
// CHECK-TXT-NEXT: include "{{.+}}";
// CHECK-TXT-EMPTY:
// CHECK-TXT-NEXT: // The program is compiled for 2 ion traps with the following configuration:
// CHECK-TXT-NEXT: //     capacities (3, 3),
// CHECK-TXT-NEXT: //     occupancies (2, 0),
// CHECK-TXT-NEXT: //     ion-bit map [0, 1],
// CHECK-TXT-NEXT: //     unused_qubits ().
// CHECK-TXT-NEXT: // Result bits of the program: the first 2 of c, the remaining bits are garbage.
// CHECK-TXT-EMPTY:
// CHECK-TXT-NEXT: creg c[2];
// CHECK-TXT-NEXT: qreg q[2];
// CHECK-TXT-NEXT: rz({{-?[0-9.]+}}) q[0];
// CHECK-TXT-NEXT: rx({{-?[0-9.]+}}) q[0];
// CHECK-TXT-NEXT: rz({{-?[0-9.]+}}) q[0];
// CHECK-TXT-NEXT: rz({{-?[0-9.]+}}) q[1];
// CHECK-TXT-NEXT: rx({{-?[0-9.]+}}) q[1];
// CHECK-TXT-NEXT: rz({{-?[0-9.]+}}) q[1];
// CHECK-TXT-NEXT: delay[{{[0-9.]+}}us] q[0],q[1];
// CHECK-TXT-NEXT: rz({{-?[0-9.]+}}) q[1];
// CHECK-TXT-NEXT: rx({{-?[0-9.]+}}) q[1];
// CHECK-TXT-NEXT: rz({{-?[0-9.]+}}) q[1];
// CHECK-TXT-NEXT: c[0] = measure q[0];
// CHECK-TXT-NEXT: c[1] = measure q[1];
// CHECK-TXT-EMPTY:

// CHECK-SIM: START
// CHECK-SIM: METADATA required_num_qubits 2
// CHECK-SIM: METADATA required_num_results 2

// We expect values 0 (|00> state) or 3 (|11> state).
// CHECK-SIM: OUTPUT INT {{[03]}}
// CHECK-SIM: OUTPUT INT {{[03]}}
// CHECK-SIM: OUTPUT INT {{[03]}}
// CHECK-SIM: OUTPUT INT {{[03]}}
// CHECK-SIM: OUTPUT INT {{[03]}}
// CHECK-SIM: END 0
