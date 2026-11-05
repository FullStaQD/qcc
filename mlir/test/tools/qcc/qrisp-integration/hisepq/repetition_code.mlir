// RUN: qcc --target=hisepq --compile-to=native %s | FileCheck %s

// GENERATED FROM QRISP VERSION 0.9.6

builtin.module @jasp_module {
  func.func public @main(%arg0: !jasp.QuantumState) -> (tensor<i64>, tensor<i64>, !jasp.QuantumState) {
    %0 = arith.constant dense<3> : tensor<i64>
    %1, %2 = "jasp.create_qubits"(%0, %arg0) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %3 = arith.constant dense<1> : tensor<i64>
    %4 = "jasp.get_qubit"(%1, %3) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %5 = "jasp.quantum_gate"(%4, %2) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %6 = arith.constant dense<0> : tensor<i64>
    %7 = arith.constant dense<2> : tensor<i64>
    %8, %9, %10, %11, %12 = scf.while (%arg30 = %1, %arg31 = %6, %arg32 = %6, %arg33 = %7, %arg34 = %5) : (!jasp.QubitArray, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState) {
      %13 = tensor.extract %arg32[] : tensor<i64>
      %14 = tensor.extract %arg33[] : tensor<i64>
      %15 = arith.cmpi slt, %13, %14 : i64
      scf.condition(%15) %arg30, %arg31, %arg32, %arg33, %arg34 : !jasp.QubitArray, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState
    } do {
    ^bb0(%arg1: !jasp.QubitArray, %arg2: tensor<i64>, %arg3: tensor<i64>, %arg4: tensor<i64>, %arg5: !jasp.QuantumState):
      %16 = arith.constant dense<2> : tensor<i64>
      %17, %18 = "jasp.create_qubits"(%16, %arg5) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
      %19 = arith.constant dense<0> : tensor<i64>
      %20 = "jasp.get_qubit"(%arg1, %19) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %21 = "jasp.get_qubit"(%17, %19) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %22 = "jasp.quantum_gate"(%20, %21, %18) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %23 = arith.constant dense<1> : tensor<i64>
      %24 = "jasp.get_qubit"(%arg1, %23) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %25 = "jasp.quantum_gate"(%24, %21, %22) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %26 = "jasp.get_qubit"(%17, %23) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %27 = "jasp.quantum_gate"(%24, %26, %25) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %28 = "jasp.get_qubit"(%arg1, %16) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %29 = "jasp.quantum_gate"(%28, %26, %27) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %30, %31 = "jasp.measure"(%17, %29) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
      %32 = "jasp.delete_qubits"(%17, %31) : (!jasp.QubitArray, !jasp.QuantumState) -> !jasp.QuantumState
      %33 = arith.constant 1 : i64
      %34 = tensor.extract %30[] : tensor<i64>
      %35 = arith.cmpi eq, %34, %33 : i64
      %36 = arith.constant true
      %37 = arith.xori %35, %36 : i1
      %38 = scf.if %37 -> (!jasp.QuantumState) {
        scf.yield %32 : !jasp.QuantumState
      } else {
        %39 = "jasp.quantum_gate"(%20, %32) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
        scf.yield %39 : !jasp.QuantumState
      }
      %40 = arith.constant 3 : i64
      %41 = tensor.extract %30[] : tensor<i64>
      %42 = arith.cmpi eq, %41, %40 : i64
      %43 = arith.constant true
      %44 = arith.xori %42, %43 : i1
      %45 = scf.if %44 -> (!jasp.QuantumState) {
        scf.yield %38 : !jasp.QuantumState
      } else {
        %46 = "jasp.quantum_gate"(%24, %38) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
        scf.yield %46 : !jasp.QuantumState
      }
      %47 = arith.constant 2 : i64
      %48 = tensor.extract %30[] : tensor<i64>
      %49 = arith.cmpi eq, %48, %47 : i64
      %50 = arith.constant true
      %51 = arith.xori %49, %50 : i1
      %52 = scf.if %51 -> (!jasp.QuantumState) {
        scf.yield %45 : !jasp.QuantumState
      } else {
        %53 = "jasp.quantum_gate"(%28, %45) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
        scf.yield %53 : !jasp.QuantumState
      }
      %54 = arith.constant 2 : i64
      %55 = tensor.extract %arg3[] : tensor<i64>
      %56 = arith.muli %55, %54 : i64
      %57 = tensor.extract %30[] : tensor<i64>
      %58 = arith.constant 0 : i64
      %59 = arith.shli %57, %56 : i64
      %60 = arith.constant 64 : i64
      %61 = arith.cmpi ugt, %60, %56 : i64
      %62 = arith.select %61, %59, %58 : i64
      %63 = tensor.extract %arg2[] : tensor<i64>
      %64 = arith.ori %63, %62 : i64
      %65 = tensor.from_elements %64 : tensor<i64>
      %66 = arith.constant 1 : i64
      %67 = tensor.extract %arg3[] : tensor<i64>
      %68 = arith.addi %67, %66 : i64
      %69 = tensor.from_elements %68 : tensor<i64>
      scf.yield %arg1, %65, %69, %arg4, %52 : !jasp.QubitArray, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState
    }
    %70, %71 = "jasp.measure"(%1, %12) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
    func.return %9, %70, %71 : tensor<i64>, tensor<i64>, !jasp.QuantumState
  }
}

// One round, checked exactly. Data qubits are 0, 1 and 2, ancillas 3 and 4. Outcomes are read from `qv.mres` right
// after each measurement.

// The error, then the syndrome extraction. Each qubit index is loaded right before its first gate.
// CHECK-LABEL: main:
// CHECK:         vmv.v.i [[D1:v[0-9]+]], 1
// CHECK-NEXT:    qv.x [[D1]], zero, 0
// CHECK-NEXT:    vmv.s.x [[D0:v[0-9]+]], zero
// CHECK-NEXT:    vmv.v.i [[A0:v[0-9]+]], 3
// CHECK-NEXT:    qv.cx [[D0]], [[A0]], 0
// CHECK-NEXT:    qv.cx [[D1]], [[A0]], 0
// CHECK-NEXT:    vmv.v.i [[A1:v[0-9]+]], 4
// CHECK-NEXT:    qv.cx [[D1]], [[A1]], 0
// CHECK-NEXT:    vmv.v.i [[D2:v[0-9]+]], 2
// CHECK-NEXT:    qv.cx [[D2]], [[A1]], 0

// The syndrome is s0 + 2 * s1.
// CHECK-NEXT:    qv.mz [[A0]], zero, 0
// CHECK-NEXT:    csrr [[S0:a[0-9]+]], qv.mres
// CHECK-NEXT:    andi [[S0]], [[S0]], 1
// CHECK-NEXT:    qv.mz [[A1]], zero, 0
// CHECK-NEXT:    csrr [[S1:a[0-9]+]], qv.mres
// CHECK-NEXT:    andi [[S1]], [[S1]], 1
// CHECK-NEXT:    slli [[S1]], [[S1]], 1
// CHECK-NEXT:    or [[S0]], [[S0]], [[S1]]

// Syndrome 1 flips data qubit 0, 3 flips data qubit 1, 2 flips data qubit 2.
// CHECK-NEXT:    li [[K:a[0-9]+]], 1
// CHECK-NEXT:    beq [[S0]], [[K]], [[FLIP0:\.LBB[0-9_]+]]
// CHECK-NEXT:    li [[K]], 3
// CHECK-NEXT:    beq [[S0]], [[K]], [[FLIP1:\.LBB[0-9_]+]]
// CHECK-NEXT:  .LBB{{[0-9_]+}}:
// CHECK-NEXT:    li [[K]], 2
// CHECK-NEXT:    bne [[S0]], [[K]], [[RESET:\.LBB[0-9_]+]]
// CHECK-NEXT:  .LBB{{[0-9_]+}}:
// CHECK-NEXT:    qv.x [[D2]], zero, 0

// Ancilla 0 is reset for the next round: measure, then flip if the outcome is 1. Same for ancilla 1.
// CHECK-NEXT:  [[RESET]]:
// CHECK-NEXT:    qv.mz [[A0]], zero, 0
// CHECK-NEXT:    csrr [[R0:a[0-9]+]], qv.mres
// CHECK-NEXT:    andi [[R0]], [[R0]], 1
// CHECK-NEXT:    beqz [[R0]], [[KEEP0:\.LBB[0-9_]+]]
// CHECK-NEXT:    qv.x [[A0]], zero, 0
// CHECK-NEXT:  [[KEEP0]]:
// CHECK-NEXT:    qv.mz [[A1]], zero, 0
// CHECK-NEXT:    csrr [[R1:a[0-9]+]], qv.mres
// CHECK-NEXT:    andi [[R1]], [[R1]], 1
// CHECK-NEXT:    beqz [[R1]], [[KEEP1:\.LBB[0-9_]+]]
// CHECK-NEXT:    qv.x [[A1]], zero, 0
// CHECK-NEXT:  [[KEEP1]]:

// The flips of data qubits 0 and 1 are placed after the return.
// CHECK:       [[FLIP0]]:
// CHECK:         qv.x [[D0]], zero, 0
// CHECK:       [[FLIP1]]:
// CHECK:         qv.x [[D1]], zero, 0
