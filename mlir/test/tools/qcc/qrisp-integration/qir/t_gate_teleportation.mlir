// RUN: qcc %s -o %t.ll
// RUN: FileCheck %s --check-prefix=CHECK-QIR < %t.ll
// RUN: qir-runner --file %t.ll -s 5 | FileCheck %s --check-prefix=CHECK-SIM

// GENERATED FROM QRISP VERSION 0.9.6

builtin.module @jasp_module {
  func.func public @main(%arg0: !jasp.QuantumState) -> (tensor<i1>, !jasp.QuantumState) {
    %0 = arith.constant dense<2> : tensor<i64>
    %1, %2 = "jasp.create_qubits"(%0, %arg0) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %3 = arith.constant dense<0> : tensor<i64>
    %4 = "jasp.get_qubit"(%1, %3) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %5 = arith.constant dense<1> : tensor<i64>
    %6 = "jasp.get_qubit"(%1, %5) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %7 = "jasp.quantum_gate"(%6, %2) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %8 = "jasp.quantum_gate"(%4, %7) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %9 = "jasp.quantum_gate"(%4, %8) {gate_type = "t"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %10 = "jasp.quantum_gate"(%6, %4, %9) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %11, %12 = "jasp.measure"(%4, %10) : (!jasp.Qubit, !jasp.QuantumState) -> (tensor<i1>, !jasp.QuantumState)
    %13 = tensor.extract %11[] : tensor<i1>
    %14 = arith.constant true
    %15 = arith.xori %13, %14 : i1
    %16 = scf.if %15 -> (!jasp.QuantumState) {
      scf.yield %12 : !jasp.QuantumState
    } else {
      %17 = "jasp.quantum_gate"(%6, %12) {gate_type = "s"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      scf.yield %17 : !jasp.QuantumState
    }
    %18 = "jasp.quantum_gate"(%6, %16) {gate_type = "t_dg"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %19 = "jasp.quantum_gate"(%6, %18) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %20, %21 = "jasp.measure"(%6, %19) : (!jasp.Qubit, !jasp.QuantumState) -> (tensor<i1>, !jasp.QuantumState)
    func.return %20, %21 : tensor<i1>, !jasp.QuantumState
  }
}

// What matters is that this contains branch instructions based on measurement:
// CHECK-QIR:   call void @__quantum__qis__mz__body(ptr null, ptr null)
// CHECK-QIR:   %[[M0:.*]] = call i1 @__quantum__rt__read_result(ptr null)
// CHECK-QIR:   br i1 %[[M0]], label %[[IF:.*]], label %[[ELSE:.*]]

// CHECK-QIR: [[IF]]:                                                ; preds = %0
// CHECK-QIR:   call void @__quantum__qis__s__body(ptr inttoptr (i64 1 to ptr))
// CHECK-QIR:   br label %[[ELSE]]

// CHECK-QIR: [[ELSE]]:                                                ; preds = %2, %0
// CHECK-QIR:   call void @__quantum__qis__t__adj(ptr inttoptr (i64 1 to ptr))


// CHECK-SIM: START
// CHECK-SIM: METADATA entry_point
// CHECK-SIM: METADATA output_labeling_schema
// CHECK-SIM: METADATA qir_profiles
// CHECK-SIM: METADATA required_num_qubits 2
// CHECK-SIM: METADATA required_num_results 2

// CHECK-SIM: OUTPUT BOOL false
// CHECK-SIM: OUTPUT BOOL false
// CHECK-SIM: OUTPUT BOOL false
// CHECK-SIM: OUTPUT BOOL false
// CHECK-SIM: OUTPUT BOOL false
