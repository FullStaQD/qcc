// RUN: qcc %s -o %t.ll
// RUN: FileCheck %s --check-prefix=CHECK-QIR < %t.ll
// RUN: qir-runner --file %t.ll -s 3 | FileCheck %s --check-prefix=CHECK-SIM

// The same program taken all the way to HiSEP-Q QISA, in builds that have that target.
// RUN: %if hisepq %{ qcc --target=hisepq --compile-to=native %s | FileCheck %s --check-prefix=CHECK-QISA %}

// GENERATED FROM QRISP VERSION 0.9.6

builtin.module @jasp_module {
  func.func public @main(%arg0: !jasp.QuantumState) -> (tensor<i64>, tensor<i64>, !jasp.QuantumState) {
    %0 = arith.constant dense<3> : tensor<i64>
    %1, %2 = "jasp.create_qubits"(%0, %arg0) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %3 = arith.constant dense<1> : tensor<i64>
    %4 = "jasp.get_qubit"(%1, %3) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %5 = "jasp.quantum_gate"(%4, %2) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %6 = arith.constant dense<0> : tensor<i64>
    %7, %8, %9, %10, %11 = scf.while (%arg30 = %1, %arg31 = %6, %arg32 = %6, %arg33 = %0, %arg34 = %5) : (!jasp.QubitArray, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState) {
      %12 = tensor.extract %arg32[] : tensor<i64>
      %13 = tensor.extract %arg33[] : tensor<i64>
      %14 = arith.cmpi slt, %12, %13 : i64
      scf.condition(%14) %arg30, %arg31, %arg32, %arg33, %arg34 : !jasp.QubitArray, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState
    } do {
    ^bb0(%arg1: !jasp.QubitArray, %arg2: tensor<i64>, %arg3: tensor<i64>, %arg4: tensor<i64>, %arg5: !jasp.QuantumState):
      %15 = arith.constant dense<2> : tensor<i64>
      %16, %17 = "jasp.create_qubits"(%15, %arg5) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
      %18 = arith.constant dense<0> : tensor<i64>
      %19 = "jasp.get_qubit"(%arg1, %18) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %20 = "jasp.get_qubit"(%16, %18) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %21 = "jasp.quantum_gate"(%19, %20, %17) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %22 = arith.constant dense<1> : tensor<i64>
      %23 = "jasp.get_qubit"(%arg1, %22) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %24 = "jasp.quantum_gate"(%23, %20, %21) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %25 = "jasp.get_qubit"(%16, %22) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %26 = "jasp.quantum_gate"(%23, %25, %24) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %27 = "jasp.get_qubit"(%arg1, %15) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %28 = "jasp.quantum_gate"(%27, %25, %26) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %29, %30 = "jasp.measure"(%16, %28) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
      %31 = "jasp.delete_qubits"(%16, %30) : (!jasp.QubitArray, !jasp.QuantumState) -> !jasp.QuantumState
      %32 = arith.constant 1 : i64
      %33 = tensor.extract %29[] : tensor<i64>
      %34 = arith.cmpi eq, %33, %32 : i64
      %35 = arith.constant true
      %36 = arith.xori %34, %35 : i1
      %37 = scf.if %36 -> (!jasp.QuantumState) {
        scf.yield %31 : !jasp.QuantumState
      } else {
        %38 = "jasp.quantum_gate"(%19, %31) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
        scf.yield %38 : !jasp.QuantumState
      }
      %39 = arith.constant 3 : i64
      %40 = tensor.extract %29[] : tensor<i64>
      %41 = arith.cmpi eq, %40, %39 : i64
      %42 = arith.constant true
      %43 = arith.xori %41, %42 : i1
      %44 = scf.if %43 -> (!jasp.QuantumState) {
        scf.yield %37 : !jasp.QuantumState
      } else {
        %45 = "jasp.quantum_gate"(%23, %37) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
        scf.yield %45 : !jasp.QuantumState
      }
      %46 = arith.constant 2 : i64
      %47 = tensor.extract %29[] : tensor<i64>
      %48 = arith.cmpi eq, %47, %46 : i64
      %49 = arith.constant true
      %50 = arith.xori %48, %49 : i1
      %51 = scf.if %50 -> (!jasp.QuantumState) {
        scf.yield %44 : !jasp.QuantumState
      } else {
        %52 = "jasp.quantum_gate"(%27, %44) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
        scf.yield %52 : !jasp.QuantumState
      }
      %53 = arith.constant 2 : i64
      %54 = tensor.extract %arg3[] : tensor<i64>
      %55 = arith.muli %54, %53 : i64
      %56 = tensor.extract %29[] : tensor<i64>
      %57 = arith.constant 0 : i64
      %58 = arith.shli %56, %55 : i64
      %59 = arith.constant 64 : i64
      %60 = arith.cmpi ugt, %59, %55 : i64
      %61 = arith.select %60, %58, %57 : i64
      %62 = tensor.extract %arg2[] : tensor<i64>
      %63 = arith.ori %62, %61 : i64
      %64 = tensor.from_elements %63 : tensor<i64>
      %65 = arith.constant 1 : i64
      %66 = tensor.extract %arg3[] : tensor<i64>
      %67 = arith.addi %66, %65 : i64
      %68 = tensor.from_elements %67 : tensor<i64>
      scf.yield %arg1, %64, %68, %arg4, %51 : !jasp.QubitArray, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState
    }
    %69, %70 = "jasp.measure"(%1, %11) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
    func.return %8, %69, %70 : tensor<i64>, tensor<i64>, !jasp.QuantumState
  }
}

// Three rounds of error correction on a 3-qubit repetition code. Each round allocates two ancillas, extracts the
// syndrome into them, gives them back, and flips the data qubit the syndrome points at. The rounds are unrolled, and a
// deallocated ancilla is not reused: every round gets fresh qubits, nine in total.

// CHECK-QIR:      call void @__quantum__qis__x__body(ptr inttoptr (i64 1 to ptr))

// Round 0: syndrome extraction on ancillas 3 and 4 ...
// CHECK-QIR:      call void @__quantum__qis__cx__body(ptr null, ptr inttoptr (i64 3 to ptr))
// CHECK-QIR-NEXT: call void @__quantum__qis__cx__body(ptr inttoptr (i64 1 to ptr), ptr inttoptr (i64 3 to ptr))
// CHECK-QIR-NEXT: call void @__quantum__qis__cx__body(ptr inttoptr (i64 1 to ptr), ptr inttoptr (i64 4 to ptr))
// CHECK-QIR-NEXT: call void @__quantum__qis__cx__body(ptr inttoptr (i64 2 to ptr), ptr inttoptr (i64 4 to ptr))
// CHECK-QIR-NEXT: call void @__quantum__qis__mz__body(ptr inttoptr (i64 3 to ptr), ptr inttoptr (i64 3 to ptr))
// CHECK-QIR:      call void @__quantum__qis__mz__body(ptr inttoptr (i64 4 to ptr), ptr inttoptr (i64 4 to ptr))

// ... then one conditional flip per data qubit, each `q_cond` a branch around an `x`.
// CHECK-QIR:      icmp ne i64 %[[S:.*]], 1
// CHECK-QIR-NEXT: br i1
// CHECK-QIR:      call void @__quantum__qis__x__body(ptr null)
// CHECK-QIR:      icmp ne i64 %[[S]], 3
// CHECK-QIR-NEXT: br i1
// CHECK-QIR:      call void @__quantum__qis__x__body(ptr inttoptr (i64 1 to ptr))
// CHECK-QIR:      icmp ne i64 %[[S]], 2
// CHECK-QIR-NEXT: br i1
// CHECK-QIR:      call void @__quantum__qis__x__body(ptr inttoptr (i64 2 to ptr))

// Rounds 1 and 2, on ancillas 5, 6 and 7, 8.
// CHECK-QIR:      call void @__quantum__qis__cx__body(ptr null, ptr inttoptr (i64 5 to ptr))
// CHECK-QIR:      call void @__quantum__qis__mz__body(ptr inttoptr (i64 6 to ptr), ptr inttoptr (i64 6 to ptr))
// CHECK-QIR:      call void @__quantum__qis__cx__body(ptr null, ptr inttoptr (i64 7 to ptr))
// CHECK-QIR:      call void @__quantum__qis__mz__body(ptr inttoptr (i64 8 to ptr), ptr inttoptr (i64 8 to ptr))

// Finally the data qubits are read out.
// CHECK-QIR:      call void @__quantum__qis__mz__body(ptr null, ptr null)
// CHECK-QIR:      call void @__quantum__qis__mz__body(ptr inttoptr (i64 1 to ptr), ptr inttoptr (i64 1 to ptr))
// CHECK-QIR:      call void @__quantum__qis__mz__body(ptr inttoptr (i64 2 to ptr), ptr inttoptr (i64 2 to ptr))

// CHECK-SIM:      METADATA required_num_qubits 9

// The flip on data qubit 1 is seen by both ancillas in round 0 (syndrome 0b11) and corrected right there, so the
// two later rounds report 0: a history of 0b000011. The data reads out as 0 afterwards.
// CHECK-SIM:      OUTPUT TUPLE 2
// CHECK-SIM-NEXT: OUTPUT INT 3
// CHECK-SIM-NEXT: OUTPUT INT 0
// CHECK-SIM:      OUTPUT TUPLE 2
// CHECK-SIM-NEXT: OUTPUT INT 3
// CHECK-SIM-NEXT: OUTPUT INT 0
// CHECK-SIM:      OUTPUT TUPLE 2
// CHECK-SIM-NEXT: OUTPUT INT 3
// CHECK-SIM-NEXT: OUTPUT INT 0

// On HiSEP-Q the corrections are branches around a `qv.x`; the measurement results they branch on are lost on this
// target, so only the shape is checked. Round 0:
// CHECK-QISA-LABEL: main:
// CHECK-QISA:         qv.x
// CHECK-QISA:         qv.cx
// CHECK-QISA:         qv.cx
// CHECK-QISA:         qv.cx
// CHECK-QISA:         qv.cx
// CHECK-QISA:         qv.mz
// CHECK-QISA:         qv.mz
// CHECK-QISA:         beqz
// The out-of-line correction blocks, three per round, nine in total.
// CHECK-QISA-COUNT-9: qv.x{{.*}}, zero, 0
// CHECK-QISA-NOT:     qv.x
