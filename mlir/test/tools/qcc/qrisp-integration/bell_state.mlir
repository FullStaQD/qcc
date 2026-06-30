// RUN: qcc %s -o %t.ll
// RUN: FileCheck %s --check-prefix=CHECK-QIR < %t.ll
// RUN: qir-runner --file %t.ll -s 5 | FileCheck %s --check-prefix=CHECK-SIM

// GENERATED FROM QRISP VERSION  git+https://github.com/eclipse-qrisp/Qrisp.git@b81ea2f979d21cd8d600e79d8b0c7066fe7cbe1b

builtin.module @jasp_module {
  func.func public @main(%arg0 : !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState) {
    %0 = arith.constant dense<2> : tensor<i64>
    %1, %2 = jasp.create_qubits %0, %arg0 : !jasp.QuantumState, tensor<i64> -> !jasp.QubitArray, !jasp.QuantumState
    %3 = arith.constant dense<0> : tensor<i64>
    %4 = jasp.get_qubit %1, %3 : !jasp.QubitArray, tensor<i64> -> !jasp.Qubit
    %5 = jasp.quantum_gate "h" (%4) , %2 : (!jasp.Qubit) , !jasp.QuantumState -> !jasp.QuantumState
    %6 = arith.constant dense<1> : tensor<i64>
    %7 = jasp.get_qubit %1, %6 : !jasp.QubitArray, tensor<i64> -> !jasp.Qubit
    %8 = jasp.quantum_gate "cx" (%4, %7) , %5 : (!jasp.Qubit, !jasp.Qubit) , !jasp.QuantumState -> !jasp.QuantumState
    %9, %10 = jasp.measure %1, %8 : !jasp.QubitArray, !jasp.QuantumState -> tensor<i64>, !jasp.QuantumState
    func.return %9, %10 : tensor<i64>, !jasp.QuantumState
  }
}

// CHECK-QIR: @__quantum__qis__h__body(ptr null)
// CHECK-QIR: @__quantum__qis__cx__body(ptr null, ptr inttoptr (i64 1 to ptr))
// CHECK-QIR-DAG: @__quantum__qis__mz__body(ptr null, ptr null)
// CHECK-QIR-DAG: @__quantum__qis__mz__body(ptr inttoptr (i64 1 to ptr), ptr inttoptr (i64 1 to ptr))

// CHECK-QIR-DAG: [[BIT0:%.+]] = call i1 @__quantum__rt__read_result(ptr null)
// CHECK-QIR-DAG: [[BIT1:%.+]] = call i1 @__quantum__rt__read_result(ptr inttoptr (i64 1 to ptr))
// CHECK-QIR-DAG: [[INT_RESULT_0:%.+]] = zext i1 [[BIT0]] to i64
// CHECK-QIR-DAG: [[INT_RESULT_1:%.+]] = zext i1 [[BIT1]] to i64

// CHECK-QIR-DAG: [[LEFT_SHIFTED_1:%.+]] = shl i64 [[INT_RESULT_1]], 1
// CHECK-QIR-DAG: [[COMBINED_INT:%.+]] = or i64 [[INT_RESULT_0]], [[LEFT_SHIFTED_1]]
// CHECK-QIR: @__quantum__rt__int_record_output(i64 [[COMBINED_INT]], ptr @.qir_dummy_label)


// CHECK-SIM: START
// CHECK-SIM: METADATA entry_point
// CHECK-SIM: METADATA output_labeling_schema
// CHECK-SIM: METADATA qir_profiles
// CHECK-SIM: METADATA required_num_qubits 2
// CHECK-SIM: METADATA required_num_results 2

// We expect values 0 (|00> state) or 3 (|11> state).
// CHECK-SIM: OUTPUT INT {{[03]}} dummy_label
// CHECK-SIM: OUTPUT INT {{[03]}} dummy_label
// CHECK-SIM: OUTPUT INT {{[03]}} dummy_label
// CHECK-SIM: OUTPUT INT {{[03]}} dummy_label
// CHECK-SIM: OUTPUT INT {{[03]}} dummy_label
