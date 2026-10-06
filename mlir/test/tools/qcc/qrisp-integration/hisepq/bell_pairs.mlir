// RUN: qcc --target=hisepq --min-vlen=128 --qubit-element-width=8 --compile-to=native %s | FileCheck %s

// GENERATED FROM QRISP VERSION 0.9.6

builtin.module @jasp_module {
  func.func public @main(%arg0: !jasp.QuantumState) -> (tensor<i1>, !jasp.QuantumState) {
    %0 = arith.constant dense<8> : tensor<i64>
    %1, %2 = "jasp.create_qubits"(%0, %arg0) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %3, %4 = "jasp.create_qubits"(%0, %2) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %5 = arith.constant dense<0> : tensor<i64>
    %6, %7, %8, %9 = scf.while (%arg25 = %1, %arg26 = %5, %arg27 = %0, %arg28 = %4) : (!jasp.QubitArray, tensor<i64>, tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, tensor<i64>, tensor<i64>, !jasp.QuantumState) {
      %10 = tensor.extract %arg26[] : tensor<i64>
      %11 = tensor.extract %arg27[] : tensor<i64>
      %12 = arith.cmpi slt, %10, %11 : i64
      scf.condition(%12) %arg25, %arg26, %arg27, %arg28 : !jasp.QubitArray, tensor<i64>, tensor<i64>, !jasp.QuantumState
    } do {
    ^bb0(%arg19: !jasp.QubitArray, %arg20: tensor<i64>, %arg21: tensor<i64>, %arg22: !jasp.QuantumState):
      %13 = "jasp.get_qubit"(%arg19, %arg20) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %14 = "jasp.quantum_gate"(%13, %arg22) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %15 = arith.constant 1 : i64
      %16 = tensor.extract %arg20[] : tensor<i64>
      %17 = arith.addi %16, %15 : i64
      %18 = tensor.from_elements %17 : tensor<i64>
      scf.yield %arg19, %18, %arg21, %14 : !jasp.QubitArray, tensor<i64>, tensor<i64>, !jasp.QuantumState
    }
    %19, %20, %21, %22, %23 = scf.while (%arg11 = %1, %arg12 = %3, %arg13 = %5, %arg14 = %0, %arg15 = %9) : (!jasp.QubitArray, !jasp.QubitArray, tensor<i64>, tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QubitArray, tensor<i64>, tensor<i64>, !jasp.QuantumState) {
      %24 = tensor.extract %arg13[] : tensor<i64>
      %25 = tensor.extract %arg14[] : tensor<i64>
      %26 = arith.cmpi slt, %24, %25 : i64
      scf.condition(%26) %arg11, %arg12, %arg13, %arg14, %arg15 : !jasp.QubitArray, !jasp.QubitArray, tensor<i64>, tensor<i64>, !jasp.QuantumState
    } do {
    ^bb1(%arg4: !jasp.QubitArray, %arg5: !jasp.QubitArray, %arg6: tensor<i64>, %arg7: tensor<i64>, %arg8: !jasp.QuantumState):
      %27 = "jasp.get_qubit"(%arg4, %arg6) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %28 = "jasp.get_qubit"(%arg5, %arg6) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %29 = "jasp.quantum_gate"(%27, %28, %arg8) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %30 = arith.constant 1 : i64
      %31 = tensor.extract %arg6[] : tensor<i64>
      %32 = arith.addi %31, %30 : i64
      %33 = tensor.from_elements %32 : tensor<i64>
      scf.yield %arg4, %arg5, %33, %arg7, %29 : !jasp.QubitArray, !jasp.QubitArray, tensor<i64>, tensor<i64>, !jasp.QuantumState
    }
    %34, %35 = "jasp.measure"(%1, %23) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
    %36, %37 = "jasp.measure"(%3, %35) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
    %38 = tensor.extract %34[] : tensor<i64>
    %39 = tensor.extract %36[] : tensor<i64>
    %40 = arith.cmpi eq, %38, %39 : i64
    %41 = tensor.from_elements %40 : tensor<i1>
    func.return %41, %37 : tensor<i1>, !jasp.QuantumState
  }
}

// Eight Bell pairs, written out one gate at a time, arrive as three QV instructions. They need only two vector
// configurations: one for the gates, one for the measurements.
// CHECK-NEXT:  vsetivli zero, 8, e8, mf2, ta, ma
// CHECK-NEXT:  vid.v [[CTRLS:v[0-9]+]]
// CHECK-NEXT:  qv.h [[CTRLS]], zero, 0
// CHECK-NEXT:  vadd.vi [[TGTS:v[0-9]+]], [[CTRLS]], 8
// CHECK-NEXT:  qv.cx [[CTRLS]], [[TGTS]], 0
// CHECK-NEXT:  vsetivli zero, 16, e8, m1, ta, ma
// CHECK-NEXT:  vid.v [[ALL:v[0-9]+]]
// CHECK-NEXT:  qv.mz [[ALL]], zero, 0
// CHECK-NEXT:  ret
