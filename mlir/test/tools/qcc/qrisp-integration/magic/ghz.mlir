// RUN: qcc %s --quantum-device=magic --device-description=%S/Inputs/device-caps-2-3.mlir --compile-to=mlir | FileCheck %s --check-prefix=CHECK-MLIR
// RUN: qcc %s --quantum-device=magic --device-description=%S/Inputs/device-caps-2-3.mlir --compile-to=custom-magic -o %t.txt
// RUN: FileCheck %s --check-prefix=CHECK-TXT < %t.txt
// RUN: magic-runner --file %t.txt --device %S/Inputs/device-caps-2-3.mlir -s 5 | FileCheck %s --check-prefix=CHECK-SIM

// GENERATED FROM QRISP VERSION 0.9.6

builtin.module @jasp_module {
  func.func public @main(%arg0: !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState) {
    %0 = arith.constant dense<3> : tensor<i64>
    %1, %2 = "jasp.create_qubits"(%0, %arg0) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %3 = arith.constant dense<0> : tensor<i64>
    %4 = "jasp.get_qubit"(%1, %3) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %5 = "jasp.quantum_gate"(%4, %2) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %6 = arith.constant dense<1> : tensor<i64>
    %7 = "jasp.get_qubit"(%1, %6) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %8 = "jasp.quantum_gate"(%4, %7, %5) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %9 = arith.constant dense<2> : tensor<i64>
    %10 = "jasp.get_qubit"(%1, %9) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %11 = "jasp.quantum_gate"(%7, %10, %8) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %12, %13 = "jasp.measure"(%1, %11) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
    func.return %12, %13 : tensor<i64>, !jasp.QuantumState
  }
}

// Three ions do not fit into trap 0 (capacity 2), so they spread: ion 0 in trap 0, ions 1 and 2 in trap 1. The
// coupling between ions 0 and 1 takes a shuttle round trip of ion 0. While it is away the empty trap 0 waits as well.
// CHECK-MLIR-DAG:  ![[T0:.*]] = !magic.ion_chain<0, [0:1]>
// CHECK-MLIR-DAG:  ![[T1:.*]] = !magic.ion_chain<1, [1:1, 2:1]>
// CHECK-MLIR-DAG:  ![[T0E:.*]] = !magic.ion_chain<0, []>
// CHECK-MLIR-DAG:  ![[T1F:.*]] = !magic.ion_chain<1, [0:1, 1:1, 2:1]>
// CHECK-MLIR:      func.func public @main() attributes {qcc.entry_point}
// CHECK-MLIR-NEXT:   magic.init : ![[T0]], ![[T1]]
// CHECK-MLIR-NOT:    magic.{{zxz|active_zz|inter_trap_zz|swap}}
// CHECK-MLIR:        magic.shuttle %{{.*}}, %{{.*}} : ![[T0]], ![[T1]] -> ![[T0E]], ![[T1F]]
// CHECK-MLIR:        magic.delay %{{.*}} {ticks = [[TICKS:[0-9]+]] : i64} : !{{.*}}
// CHECK-MLIR:        magic.delay %{{.*}} {ticks = [[TICKS]] : i64} : ![[T0E]]
// CHECK-MLIR:        magic.shuttle %{{.*}}, %{{.*}} : ![[T1F]], ![[T0E]] -> ![[T1]], ![[T0]]
// CHECK-MLIR-NOT:    magic.{{zxz|active_zz|inter_trap_zz|swap}}
// CHECK-MLIR:        %[[M0:.*]] = magic.mzd %{{.*}} : ![[T0]] -> i1
// CHECK-MLIR-NEXT:   %[[M12:.*]]:2 = magic.mzd %{{.*}} : ![[T1]] -> i1, i1
// CHECK-MLIR-NEXT:   aux.record_int %[[M0]] : i1
// CHECK-MLIR-NEXT:   aux.record_int %[[M12]]#0 : i1
// CHECK-MLIR-NEXT:   aux.record_int %[[M12]]#1 : i1
// CHECK-MLIR-NEXT:   return

// CHECK-TXT:      OPENQASM 3.0;
// CHECK-TXT-NEXT: include "{{.+}}";
// CHECK-TXT-EMPTY:
// CHECK-TXT-NEXT: // The program is compiled for 2 ion traps with the following configuration:
// CHECK-TXT-NEXT: //     capacities (2, 3),
// CHECK-TXT-NEXT: //     occupancies (1, 2),
// CHECK-TXT-NEXT: //     ion-bit map [0, 1, 2],
// CHECK-TXT-NEXT: //     unused_qubits ().
// CHECK-TXT-NEXT: // Result bits of the program: the first 3 of c, the remaining bits are garbage.
// CHECK-TXT-EMPTY:
// CHECK-TXT-NEXT: creg c[3];
// CHECK-TXT-NEXT: qreg q[3];
// CHECK-TXT-NEXT: rz({{-?[0-9.]+}}) q[0];
// CHECK-TXT-NEXT: rx({{-?[0-9.]+}}) q[0];
// CHECK-TXT-NEXT: rz({{-?[0-9.]+}}) q[0];
// CHECK-TXT:      shuttle(0,1) q[0];
// CHECK-TXT-NEXT: recode q[2];
// CHECK-TXT-NEXT: delay[[[T:[0-9.]+]]us] q[0],q[1],q[2];
// CHECK-TXT-NEXT: recode q[2];
// The format has no delay without qubits, so the wait of the empty trap is a comment.
// CHECK-TXT-NEXT: // delay[[[T]]us] <empty trap 0>
// CHECK-TXT-NEXT: shuttle(1,0) q[0];
// The coupling between ions 1 and 2 stays within trap 1 and needs no shuttle.
// CHECK-TXT:      delay[{{[0-9.]+}}us] q[1],q[2];
// CHECK-TXT:      c[0] = measure q[0];
// CHECK-TXT-NEXT: c[1] = measure q[1];
// CHECK-TXT-NEXT: c[2] = measure q[2];
// CHECK-TXT-EMPTY:

// CHECK-SIM: START
// CHECK-SIM: METADATA required_num_qubits 3
// CHECK-SIM: METADATA required_num_results 3

// We expect values 0 (|000> state) or 7 (|111> state).
// CHECK-SIM: OUTPUT INT {{[07]}}
// CHECK-SIM: OUTPUT INT {{[07]}}
// CHECK-SIM: OUTPUT INT {{[07]}}
// CHECK-SIM: OUTPUT INT {{[07]}}
// CHECK-SIM: OUTPUT INT {{[07]}}
// CHECK-SIM: END 0
