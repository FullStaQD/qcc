// RUN: qcc-opt %s -jasp-to-qc | FileCheck %s

// CHECK-LABEL: func @test_simple_circuit
func.func @test_simple_circuit() -> tensor<i1> {
    %state0 = jasp.create_quantum_kernel -> !jasp.QuantumState
    // Quantum State management leaves no trace in QC IR.

    %num_qubits = arith.constant dense<1> : tensor<i64>
    // CHECK: [[NUM_QUBITS_TENSOR:%.+]] = arith.constant dense<1> : tensor<i64>
    %qubit_array, %state1 = jasp.create_qubits %num_qubits, %state0 : !jasp.QuantumState, tensor<i64> -> !jasp.QubitArray, !jasp.QuantumState
    // memref.alloc needs a size of index type, not of tensor type.
    // CHECK: [[NUM_QUBITS_i64:%.+]] = tensor.extract [[NUM_QUBITS_TENSOR]][] : tensor<i64>
    // CHECK: [[NUM_QUBITS:%.+]] = arith.index_cast [[NUM_QUBITS_i64]] : i64 to index
    // CHECK: [[QUBIT_ARRAY:%.+]] = memref.alloc([[NUM_QUBITS]]) : memref<?x!qc.qubit>

    %qubit_index = arith.constant dense<0> : tensor<i64>
    // CHECK: [[QUBIT_INDEX_TENSOR:%.+]] = arith.constant dense<0> : tensor<i64>
    %qubit_reference = jasp.get_qubit %qubit_array, %qubit_index : !jasp.QubitArray, tensor<i64> -> !jasp.Qubit
    // memref.load needs an index of index type, not of tensor type.
    // CHECK: [[QUBIT_INDEX_i64:%.+]] = tensor.extract [[QUBIT_INDEX_TENSOR]][] : tensor<i64>
    // CHECK: [[QUBIT_INDEX:%.+]] = arith.index_cast [[QUBIT_INDEX_i64]] : i64 to index
    // CHECK: [[QUBIT_REFERENCE:%.+]] = memref.load [[QUBIT_ARRAY]][[[QUBIT_INDEX]]] : memref<?x!qc.qubit>

    %state2 = jasp.quantum_gate "h" (%qubit_reference), %state1 : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
    // CHECK: qc.h [[QUBIT_REFERENCE]] : !qc.qubit

    %random_bit, %state3 = jasp.measure %qubit_reference, %state2 : !jasp.Qubit, !jasp.QuantumState -> tensor<i1>, !jasp.QuantumState
    // CHECK: [[RANDOM_BIT:%.+]] = qc.measure [[QUBIT_REFERENCE]] : !qc.qubit

    %state4 = jasp.delete_qubits %qubit_array, %state3 : !jasp.QubitArray, !jasp.QuantumState -> !jasp.QuantumState
    // CHECK: memref.dealloc [[QUBIT_ARRAY]] : memref<?x!qc.qubit>

    %success = jasp.consume_quantum_kernel %state4 : !jasp.QuantumState -> tensor<i1>
    // We do not lower the functionality of returning a success value
    // for the kernel execution. A constant value of 1 is returned,
    // assuming a successful execution.
    // CHECK: [[SUCCESS:%.+]] = arith.constant true

    return %random_bit : tensor<i1>
    // CHECK: return [[RANDOM_BIT]] : i1
}

/// Test that measuring a qubit array returns a packed i64 constructed by a for loop.
// CHECK-LABEL: func @test_dyn_arr_measure
// CHECK-SAME: ([[NUM_QUBITS:%.+]]: i64)
func.func @test_dyn_arr_measure(%num_qubits : tensor<i64>) -> tensor<i64> {
    %state0 = jasp.create_quantum_kernel -> !jasp.QuantumState
    // CHECK-DAG: [[NUM_QUBITS_i64:%.+]] = arith.index_cast [[NUM_QUBITS]] : i64 to index
    // CHECK-DAG: [[STEP:%.+]] = arith.constant 1 : index
    // CHECK-DAG: [[ZERO:%.+]] = arith.constant 0 : index
    // CHECK-DAG: [[ZERO_i64:%.+]] = arith.constant 0 : i64

    %q_arr, %state1 = jasp.create_qubits %num_qubits, %state0 : !jasp.QuantumState, tensor<i64> -> !jasp.QubitArray, !jasp.QuantumState
    // CHECK-DAG: [[Q_ARR:%.+]] = memref.alloc([[NUM_QUBITS_i64]]) : memref<?x!qc.qubit>
    // CHECK-DAG: [[QUBIT_ARRAY_DIM:%.+]] = memref.dim [[Q_ARR]], [[ZERO]] : memref<?x!qc.qubit>
    // The qubit array measurement is implemented as a for loop.
    %result, %state2 = jasp.measure %q_arr, %state1 : !jasp.QubitArray, !jasp.QuantumState -> tensor<i64>, !jasp.QuantumState
    // CHECK: [[MEASURE_INT:%.+]] = scf.for [[IV:%.+]] = [[ZERO]] to [[QUBIT_ARRAY_DIM]] step [[STEP]] iter_args([[INT_ACC:%.+]] = [[ZERO_i64]]) -> (i64)  {
    // CHECK-DAG: [[QUBIT:%.+]] = memref.load [[Q_ARR]][[[IV]]] : memref<?x!qc.qubit>
    // CHECK-DAG: [[MEASURED_BIT:%.+]] = qc.measure [[QUBIT]]
    // CHECK-DAG: [[MEASURED_INT:%.+]] = arith.extui [[MEASURED_BIT]] : i1 to i64
    // CHECK-DAG: [[SHIFT_POS:%.+]] = arith.index_cast [[IV]] : index to i64
    // CHECK-DAG: [[SHIFTED_INT:%.+]] = arith.shli [[MEASURED_INT]], [[SHIFT_POS]]
    // CHECK-DAG: [[NEW_INT_ACC:%.+]] = arith.ori [[INT_ACC]], [[SHIFTED_INT]]
    // CHECK-DAG: scf.yield [[NEW_INT_ACC]] : i64

    %state3 = jasp.delete_qubits %q_arr, %state2 : !jasp.QubitArray, !jasp.QuantumState -> !jasp.QuantumState
    // CHECK: memref.dealloc

    %success = jasp.consume_quantum_kernel %state3 : !jasp.QuantumState -> tensor<i1>

    return %result : tensor<i64>
    // CHECK: return [[MEASURE_INT]] : i64
}
