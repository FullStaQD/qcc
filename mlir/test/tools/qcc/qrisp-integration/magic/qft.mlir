// RUN: qcc %s --quantum-device=magic --device-description=%S/Inputs/device-2x3.mlir --compile-to=mlir | FileCheck %s --check-prefix=CHECK-MLIR
// RUN: qcc %s --quantum-device=magic --device-description=%S/Inputs/device-2x3.mlir --compile-to=custom-magic -o %t.txt
// RUN: FileCheck %s --check-prefix=CHECK-TXT < %t.txt
// RUN: magic-runner --file %t.txt --device %S/Inputs/device-2x3.mlir --probabilities | FileCheck %s --check-prefix=CHECK-SIM

// GENERATED FROM QRISP VERSION 0.9.6

builtin.module @jasp_module {
  func.func public @main(%arg0: !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState) {
    %0 = arith.constant dense<4> : tensor<i64>
    %1, %2 = "jasp.create_qubits"(%0, %arg0) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %3 = arith.constant dense<0> : tensor<i64>
    %4 = "jasp.get_qubit"(%1, %3) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %5 = "jasp.quantum_gate"(%4, %2) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %6 = arith.constant dense<-15.707963267948966> : tensor<f64>
    %7 = "jasp.quantum_gate"(%4, %6, %5) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %8 = arith.constant dense<1> : tensor<i64>
    %9 = "jasp.get_qubit"(%1, %8) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %10 = "jasp.quantum_gate"(%9, %7) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %11 = arith.constant dense<-7.8539816339744828> : tensor<f64>
    %12 = "jasp.quantum_gate"(%9, %11, %10) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %13 = arith.constant dense<2> : tensor<i64>
    %14 = "jasp.get_qubit"(%1, %13) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %15 = "jasp.quantum_gate"(%14, %12) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %16 = arith.constant dense<-3.9269908169872414> : tensor<f64>
    %17 = "jasp.quantum_gate"(%14, %16, %15) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %18 = arith.constant dense<3> : tensor<i64>
    %19 = "jasp.get_qubit"(%1, %18) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %20 = "jasp.quantum_gate"(%19, %17) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %21 = arith.constant dense<-1.9634954084936207> : tensor<f64>
    %22 = "jasp.quantum_gate"(%19, %21, %20) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %23 = "jasp.quantum_gate"(%4, %22) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %24 = arith.constant dense<0.78539816339744828> : tensor<f64>
    %25 = "jasp.quantum_gate"(%4, %24, %23) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %26 = "jasp.quantum_gate"(%9, %24, %25) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %27 = "jasp.quantum_gate"(%9, %4, %26) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %28 = arith.constant dense<-0.78539816339744828> : tensor<f64>
    %29 = "jasp.quantum_gate"(%4, %28, %27) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %30 = "jasp.quantum_gate"(%9, %4, %29) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %31 = arith.constant dense<0.39269908169872414> : tensor<f64>
    %32 = "jasp.quantum_gate"(%4, %31, %30) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %33 = "jasp.quantum_gate"(%14, %31, %32) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %34 = "jasp.quantum_gate"(%14, %4, %33) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %35 = arith.constant dense<-0.39269908169872414> : tensor<f64>
    %36 = "jasp.quantum_gate"(%4, %35, %34) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %37 = "jasp.quantum_gate"(%14, %4, %36) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %38 = arith.constant dense<0.19634954084936207> : tensor<f64>
    %39 = "jasp.quantum_gate"(%4, %38, %37) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %40 = "jasp.quantum_gate"(%19, %38, %39) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %41 = "jasp.quantum_gate"(%19, %4, %40) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %42 = arith.constant dense<-0.19634954084936207> : tensor<f64>
    %43 = "jasp.quantum_gate"(%4, %42, %41) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %44 = "jasp.quantum_gate"(%19, %4, %43) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %45 = "jasp.quantum_gate"(%9, %44) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %46 = "jasp.quantum_gate"(%9, %24, %45) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %47 = "jasp.quantum_gate"(%14, %24, %46) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %48 = "jasp.quantum_gate"(%14, %9, %47) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %49 = "jasp.quantum_gate"(%9, %28, %48) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %50 = "jasp.quantum_gate"(%14, %9, %49) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %51 = "jasp.quantum_gate"(%9, %31, %50) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %52 = "jasp.quantum_gate"(%19, %31, %51) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %53 = "jasp.quantum_gate"(%19, %9, %52) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %54 = "jasp.quantum_gate"(%9, %35, %53) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %55 = "jasp.quantum_gate"(%19, %9, %54) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %56 = "jasp.quantum_gate"(%14, %55) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %57 = "jasp.quantum_gate"(%14, %24, %56) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %58 = "jasp.quantum_gate"(%19, %24, %57) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %59 = "jasp.quantum_gate"(%19, %14, %58) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %60 = "jasp.quantum_gate"(%14, %28, %59) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
    %61 = "jasp.quantum_gate"(%19, %14, %60) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %62 = "jasp.quantum_gate"(%19, %61) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %63, %64 = "jasp.measure"(%1, %62) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
    func.return %63, %64 : tensor<i64>, !jasp.QuantumState
  }
}

// Four ions on two traps of capacity 3: two per trap, one slot stays free in each for shuttling. The QFT couples
// every pair of qubits, so ions travel between the traps several times.
// CHECK-MLIR-DAG:  ![[T0:.*]] = !magic.ion_chain<0, [0:1, 1:1]>
// CHECK-MLIR-DAG:  ![[T1:.*]] = !magic.ion_chain<1, [2:1, 3:1]>
// CHECK-MLIR:      func.func public @main() attributes {qcc.entry_point}
// CHECK-MLIR-NEXT:   magic.init : ![[T0]], ![[T1]]
// CHECK-MLIR-NOT:    magic.{{zxz|active_zz|inter_trap_zz|swap}}
// CHECK-MLIR:        magic.delay
// CHECK-MLIR:        magic.shuttle
// CHECK-MLIR:        magic.shuttle
// CHECK-MLIR-NOT:    magic.{{zxz|active_zz|inter_trap_zz|swap}}
// CHECK-MLIR:        %[[MA:.*]]:2 = magic.mzd %{{.*}} : ![[T0]] -> i1, i1
// CHECK-MLIR-NEXT:   %[[MB:.*]]:2 = magic.mzd %{{.*}} : ![[T1]] -> i1, i1
// CHECK-MLIR-NEXT:   aux.record_int %[[MA]]#0 : i1
// CHECK-MLIR-NEXT:   aux.record_int %[[MA]]#1 : i1
// CHECK-MLIR-NEXT:   aux.record_int %[[MB]]#0 : i1
// CHECK-MLIR-NEXT:   aux.record_int %[[MB]]#1 : i1
// CHECK-MLIR-NEXT:   return

// CHECK-TXT:      OPENQASM 3.0;
// CHECK-TXT-NEXT: include "{{.+}}";
// CHECK-TXT-EMPTY:
// CHECK-TXT-NEXT: // The program is compiled for 2 ion traps with the following configuration:
// CHECK-TXT-NEXT: //     capacities (3, 3),
// CHECK-TXT-NEXT: //     occupancies (2, 2),
// CHECK-TXT-NEXT: //     ion-bit map [0, 1, 2, 3],
// CHECK-TXT-NEXT: //     unused_qubits ().
// CHECK-TXT-NEXT: // Result bits of the program: the first 4 of c, the remaining bits are garbage.
// CHECK-TXT-EMPTY:
// CHECK-TXT-NEXT: creg c[4];
// CHECK-TXT-NEXT: qreg q[4];
// CHECK-TXT:      delay[{{[0-9.]+}}us] q[0],q[1];
// The idle trap waits with its ions switched off.
// CHECK-TXT:      recode q[2];
// CHECK-TXT-NEXT: recode q[3];
// CHECK-TXT-NEXT: delay[{{[0-9.]+}}us] q[2],q[3];
// CHECK-TXT-NEXT: recode q[2];
// CHECK-TXT-NEXT: recode q[3];
// CHECK-TXT-NEXT: shuttle(0,1) q[0];
// CHECK-TXT:      shuttle(1,0) q[0];
// CHECK-TXT:      c[0] = measure q[0];
// CHECK-TXT-NEXT: c[1] = measure q[1];
// CHECK-TXT-NEXT: c[2] = measure q[2];
// CHECK-TXT-NEXT: c[3] = measure q[3];
// CHECK-TXT-EMPTY:

// The input is prepared such that the QFT yields the basis state |5>.
// CHECK-SIM:      START
// CHECK-SIM-NEXT: METADATA required_num_qubits 4
// CHECK-SIM-NEXT: METADATA required_num_results 4
// CHECK-SIM-NEXT: PROBABILITY INT 5 1.000000
// CHECK-SIM-NEXT: END 0
