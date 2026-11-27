// RUN: qcc-opt %s --convert-jasp-to-qref --split-input-file | FileCheck %s

// CHECK-LABEL: func.func @kernel() -> i1
func.func @kernel() -> tensor<i1> {
  %s0 = "jasp.create_quantum_kernel"() : () -> !jasp.QuantumState
  %n = arith.constant dense<2> : tensor<i64>
  %q, %s1 = "jasp.create_qubits"(%n, %s0) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
  %i = arith.constant dense<1> : tensor<i64>
  %q1 = "jasp.get_qubit"(%q, %i) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
  %s2 = "jasp.quantum_gate"(%q1, %s1) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %bit, %s3 = "jasp.measure"(%q1, %s2) : (!jasp.Qubit, !jasp.QuantumState) -> (tensor<i1>, !jasp.QuantumState)
  %s4 = "jasp.reset"(%q1, %s3) : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s5 = "jasp.delete_qubits"(%q, %s4) : (!jasp.QubitArray, !jasp.QuantumState) -> !jasp.QuantumState
  %success = "jasp.consume_quantum_kernel"(%s5) : (!jasp.QuantumState) -> tensor<i1>
  return %bit : tensor<i1>
}

// CHECK:      %[[N_TENSOR:.*]] = arith.constant dense<2> : tensor<i64>
// CHECK-NEXT: %[[N_I64:.*]] = tensor.extract %[[N_TENSOR]][] : tensor<i64>
// CHECK-NEXT: %[[N:.*]] = arith.index_cast %[[N_I64]] : i64 to index
// CHECK-NEXT: %[[Q:.*]] = qcc.alloc %[[N]] : tensor<?x!qcc.qubit_ref>
// CHECK-NEXT: %[[I_TENSOR:.*]] = arith.constant dense<1> : tensor<i64>
// CHECK-NEXT: %[[I_I64:.*]] = tensor.extract %[[I_TENSOR]][] : tensor<i64>
// CHECK-NEXT: %[[I:.*]] = arith.index_cast %[[I_I64]] : i64 to index
// CHECK-NEXT: %[[Q1:.*]] = tensor.extract %[[Q]][%[[I]]] : tensor<?x!qcc.qubit_ref>
// CHECK-NEXT: qref.single h %[[Q1]] : !qcc.qubit_ref
// CHECK-NEXT: %[[BIT:.*]] = qref.measure z %[[Q1]] : !qcc.qubit_ref -> i1
// CHECK-NEXT: qref.reset z %[[Q1]] : !qcc.qubit_ref
// CHECK-NEXT: qcc.dealloc %[[Q]] : tensor<?x!qcc.qubit_ref>
// The kernel is assumed to succeed.
// CHECK-NEXT: arith.constant true
// CHECK-NEXT: return %[[BIT]] : i1

// -----

// The quantum state is dropped from signatures, calls and returns.
// CHECK-LABEL: func.func @array(
// CHECK-SAME:      %[[Q:.*]]: tensor<?x!qcc.qubit_ref>) -> (i64, i64)
func.func @array(%q: !jasp.QubitArray, %s0: !jasp.QuantumState) -> (tensor<i64>, tensor<i64>, !jasp.QuantumState) {
  %size = "jasp.get_size"(%q) : (!jasp.QubitArray) -> tensor<i64>
  %s1 = "jasp.reset"(%q, %s0) : (!jasp.QubitArray, !jasp.QuantumState) -> !jasp.QuantumState
  %bits, %s2 = "jasp.measure"(%q, %s1) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
  return %size, %bits, %s2 : tensor<i64>, tensor<i64>, !jasp.QuantumState
}

// CHECK:      %[[C0:.*]] = arith.constant 0 : index
// CHECK-NEXT: %[[DIM:.*]] = tensor.dim %[[Q]], %[[C0]] : tensor<?x!qcc.qubit_ref>
// CHECK-NEXT: %[[SIZE:.*]] = arith.index_cast %[[DIM]] : index to i64
// CHECK:      scf.for %[[IV:.*]] =
// CHECK-NEXT:   %[[QI:.*]] = tensor.extract %[[Q]][%[[IV]]] : tensor<?x!qcc.qubit_ref>
// CHECK-NEXT:   qref.reset z %[[QI]] : !qcc.qubit_ref
// CHECK-NEXT: }
// CHECK:      %[[ZERO:.*]] = arith.constant 0 : i64
// CHECK-NEXT: %[[C64:.*]] = arith.constant 64 : i64
// CHECK:      %[[BITS:.*]] = scf.for %[[IV:.*]] = %{{.*}} to %{{.*}} step %{{.*}} iter_args(%[[ACC:.*]] = %[[ZERO]]) -> (i64) {
// CHECK-NEXT:   %[[QI:.*]] = tensor.extract %[[Q]][%[[IV]]] : tensor<?x!qcc.qubit_ref>
// CHECK-NEXT:   %[[BIT:.*]] = qref.measure z %[[QI]] : !qcc.qubit_ref -> i1
// CHECK-NEXT:   %[[BIT_I64:.*]] = arith.extui %[[BIT]] : i1 to i64
// CHECK-NEXT:   %[[IV_I64:.*]] = arith.index_cast %[[IV]] : index to i64
// CHECK-NEXT:   %[[IN_RANGE:.*]] = arith.cmpi ult, %[[IV_I64]], %[[C64]] : i64
// CHECK-NEXT:   %[[AMOUNT:.*]] = arith.select %[[IN_RANGE]], %[[IV_I64]], %[[ZERO]] : i64
// CHECK-NEXT:   %[[SHIFTED:.*]] = arith.shli %[[BIT_I64]], %[[AMOUNT]] : i64
// CHECK-NEXT:   %[[KEPT:.*]] = arith.select %[[IN_RANGE]], %[[SHIFTED]], %[[ZERO]] : i64
// CHECK-NEXT:   %[[NEW_ACC:.*]] = arith.ori %[[ACC]], %[[KEPT]] : i64
// CHECK-NEXT:   scf.yield %[[NEW_ACC]] : i64
// CHECK-NEXT: }
// CHECK-NEXT: return %[[SIZE]], %[[BITS]] : i64, i64

// -----

// A loop carries the array, but not the quantum state.
// CHECK-LABEL: func.func @loop(
// CHECK-SAME:      %[[Q:.*]]: tensor<?x!qcc.qubit_ref>, %{{.*}}: i64) {
func.func @loop(%q: !jasp.QubitArray, %s0: !jasp.QuantumState, %n: tensor<i64>) -> !jasp.QuantumState {
  %c0 = arith.constant dense<0> : tensor<i64>
  %r:3 = scf.while (%i = %c0, %a = %q, %s = %s0)
      : (tensor<i64>, !jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QubitArray, !jasp.QuantumState) {
    %iv = tensor.extract %i[] : tensor<i64>
    %nv = tensor.extract %n[] : tensor<i64>
    %cond = arith.cmpi slt, %iv, %nv : i64
    scf.condition(%cond) %i, %a, %s : tensor<i64>, !jasp.QubitArray, !jasp.QuantumState
  } do {
  ^bb0(%i: tensor<i64>, %a: !jasp.QubitArray, %s: !jasp.QuantumState):
    %qi = "jasp.get_qubit"(%a, %i) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %s1 = "jasp.quantum_gate"(%qi, %s) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %iv = tensor.extract %i[] : tensor<i64>
    %c1 = arith.constant 1 : i64
    %next = arith.addi %iv, %c1 : i64
    %nt = tensor.from_elements %next : tensor<i64>
    scf.yield %nt, %a, %s1 : tensor<i64>, !jasp.QubitArray, !jasp.QuantumState
  }
  return %r#2 : !jasp.QuantumState
}

// CHECK:      scf.while (%{{.*}} = %{{.*}}, %{{.*}} = %[[Q]]) : (i64, tensor<?x!qcc.qubit_ref>) -> (i64, tensor<?x!qcc.qubit_ref>) {
// CHECK:        scf.condition(%{{.*}}) %{{.*}}, %{{.*}} : i64, tensor<?x!qcc.qubit_ref>
// CHECK:      ^bb0(%[[I:.*]]: i64, %[[A:.*]]: tensor<?x!qcc.qubit_ref>):
// CHECK:        %[[INDEX:.*]] = arith.index_cast %[[I]] : i64 to index
// CHECK-NEXT:   %[[QI:.*]] = tensor.extract %[[A]][%[[INDEX]]] : tensor<?x!qcc.qubit_ref>
// CHECK-NEXT:   qref.single x %[[QI]] : !qcc.qubit_ref
// CHECK:        scf.yield %{{.*}}, %[[A]] : i64, tensor<?x!qcc.qubit_ref>
// CHECK:      return

// -----

// CHECK-LABEL: func.func @gates(
// CHECK-SAME:      %[[Q0:.*]]: !qcc.qubit_ref, %[[Q1:.*]]: !qcc.qubit_ref, %[[A:.*]]: f64, %[[B:.*]]: f64, %[[C:.*]]: f64)
func.func @gates(%q0: !jasp.Qubit, %q1: !jasp.Qubit, %a: tensor<f64>, %b: tensor<f64>, %c: tensor<f64>,
                 %s0: !jasp.QuantumState) -> !jasp.QuantumState {
  %s1 = "jasp.quantum_gate"(%q0, %s0) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s2 = "jasp.quantum_gate"(%q0, %s1) {gate_type = "y"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s3 = "jasp.quantum_gate"(%q0, %s2) {gate_type = "z"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s4 = "jasp.quantum_gate"(%q0, %s3) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s5 = "jasp.quantum_gate"(%q0, %s4) {gate_type = "s"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s6 = "jasp.quantum_gate"(%q0, %s5) {gate_type = "s_dg"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s7 = "jasp.quantum_gate"(%q0, %s6) {gate_type = "t"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s8 = "jasp.quantum_gate"(%q0, %s7) {gate_type = "t_dg"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s9 = "jasp.quantum_gate"(%q0, %s8) {gate_type = "sx"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s10 = "jasp.quantum_gate"(%q0, %s9) {gate_type = "id"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s11 = "jasp.quantum_gate"(%a, %s10) {gate_type = "gphase"} : (tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
  %s12 = "jasp.quantum_gate"(%q0, %a, %s11) {gate_type = "rx"}
      : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
  %s13 = "jasp.quantum_gate"(%q0, %a, %s12) {gate_type = "ry"}
      : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
  %s14 = "jasp.quantum_gate"(%q0, %a, %s13) {gate_type = "rz"}
      : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
  %s15 = "jasp.quantum_gate"(%q0, %a, %s14) {gate_type = "p"}
      : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
  %s16 = "jasp.quantum_gate"(%q0, %a, %b, %c, %s15) {gate_type = "u3"}
      : (!jasp.Qubit, tensor<f64>, tensor<f64>, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
  %s17 = "jasp.quantum_gate"(%q0, %q1, %s16) {gate_type = "cx"}
      : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s18 = "jasp.quantum_gate"(%q0, %q1, %s17) {gate_type = "cy"}
      : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s19 = "jasp.quantum_gate"(%q0, %q1, %s18) {gate_type = "cz"}
      : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s20 = "jasp.quantum_gate"(%q0, %q1, %s19) {gate_type = "swap"}
      : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
  %s21 = "jasp.quantum_gate"(%q0, %q1, %a, %s20) {gate_type = "cp"}
      : (!jasp.Qubit, !jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
  %s22 = "jasp.quantum_gate"(%q0, %q1, %a, %s21) {gate_type = "crz"}
      : (!jasp.Qubit, !jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
  %s23 = "jasp.quantum_gate"(%q0, %q1, %a, %s22) {gate_type = "rxx"}
      : (!jasp.Qubit, !jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
  %s24 = "jasp.quantum_gate"(%q0, %q1, %a, %s23) {gate_type = "rzz"}
      : (!jasp.Qubit, !jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
  return %s24 : !jasp.QuantumState
}

// CHECK-NEXT: qref.single x %[[Q0]] : !qcc.qubit_ref
// CHECK-NEXT: qref.single y %[[Q0]] : !qcc.qubit_ref
// CHECK-NEXT: qref.single z %[[Q0]] : !qcc.qubit_ref
// CHECK-NEXT: qref.single h %[[Q0]] : !qcc.qubit_ref
// CHECK-NEXT: qref.single s %[[Q0]] : !qcc.qubit_ref
// CHECK-NEXT: qref.single sdg %[[Q0]] : !qcc.qubit_ref
// CHECK-NEXT: qref.single t %[[Q0]] : !qcc.qubit_ref
// CHECK-NEXT: qref.single tdg %[[Q0]] : !qcc.qubit_ref
// CHECK-NEXT: qref.single sx %[[Q0]] : !qcc.qubit_ref
// `id` and `gphase` are dropped.
// CHECK-NEXT: qref.single rx(%[[A]]) %[[Q0]] : f64, !qcc.qubit_ref
// CHECK-NEXT: qref.single ry(%[[A]]) %[[Q0]] : f64, !qcc.qubit_ref
// CHECK-NEXT: qref.single rz(%[[A]]) %[[Q0]] : f64, !qcc.qubit_ref
// CHECK-NEXT: qref.single rz(%[[A]]) %[[Q0]] : f64, !qcc.qubit_ref
// CHECK-NEXT: qref.single u_zyz(%[[C]], %[[A]], %[[B]]) %[[Q0]] : f64, !qcc.qubit_ref
// CHECK-NEXT: qref.pair cx %[[Q0]], %[[Q1]] : !qcc.qubit_ref
// CHECK-NEXT: qref.pair cy %[[Q0]], %[[Q1]] : !qcc.qubit_ref
// CHECK-NEXT: qref.pair cz %[[Q0]], %[[Q1]] : !qcc.qubit_ref
// CHECK-NEXT: qref.pair swap %[[Q0]], %[[Q1]] : !qcc.qubit_ref
// CHECK-NEXT: qref.pair cp(%[[A]]) %[[Q0]], %[[Q1]] : f64, !qcc.qubit_ref
// CHECK-NEXT: qref.pair crz(%[[A]]) %[[Q0]], %[[Q1]] : f64, !qcc.qubit_ref
// CHECK-NEXT: qref.pair rxx(%[[A]]) %[[Q0]], %[[Q1]] : f64, !qcc.qubit_ref
// CHECK-NEXT: qref.pair rzz(%[[A]]) %[[Q0]], %[[Q1]] : f64, !qcc.qubit_ref
// CHECK-NEXT: return
