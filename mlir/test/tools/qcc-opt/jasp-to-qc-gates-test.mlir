// RUN: qcc-opt %s --jasp-to-qc | FileCheck %s

module @jasp_module {
  func.func private @main(%state_in: !jasp.QuantumState, %q0: !jasp.Qubit, %q1: !jasp.Qubit) -> () {
    %f1 = arith.constant dense<1.0> : tensor<f64>
    %f2 = arith.constant dense<2.0> : tensor<f64>
    %f3 = arith.constant dense<3.0> : tensor<f64>

    %s0 = jasp.quantum_gate "x"(%q0), %state_in : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
    %s1 = jasp.quantum_gate "y"(%q0), %s0 : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
    %s2 = jasp.quantum_gate "z"(%q0), %s1 : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
    %s3 = jasp.quantum_gate "h"(%q0), %s2 : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
    %s4 = jasp.quantum_gate "s"(%q0), %s3 : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
    %s5 = jasp.quantum_gate "t"(%q0), %s4 : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
    %s6 = jasp.quantum_gate "sx"(%q0), %s5 : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
    %s7 = jasp.quantum_gate "id"(%q0), %s6 : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState

    %s8 = jasp.quantum_gate "p"(%q0, %f1), %s7 : (!jasp.Qubit, tensor<f64>), !jasp.QuantumState -> !jasp.QuantumState
    %s9 = jasp.quantum_gate "rx"(%q0, %f1), %s8 : (!jasp.Qubit, tensor<f64>), !jasp.QuantumState -> !jasp.QuantumState
    %s10 = jasp.quantum_gate "ry"(%q0, %f1), %s9 : (!jasp.Qubit, tensor<f64>), !jasp.QuantumState -> !jasp.QuantumState
    %s11 = jasp.quantum_gate "rz"(%q0, %f1), %s10 : (!jasp.Qubit, tensor<f64>), !jasp.QuantumState -> !jasp.QuantumState
    %s12 = jasp.quantum_gate "u3"(%q0, %f1, %f2, %f3), %s11 : (!jasp.Qubit, tensor<f64>, tensor<f64>, tensor<f64>), !jasp.QuantumState -> !jasp.QuantumState

    %s13 = jasp.quantum_gate "cx"(%q0, %q1), %s12 : (!jasp.Qubit, !jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
    %s14 = jasp.quantum_gate "cy"(%q0, %q1), %s13 : (!jasp.Qubit, !jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
    %s15 = jasp.quantum_gate "cz"(%q0, %q1), %s14 : (!jasp.Qubit, !jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
    %s16 = jasp.quantum_gate "swap"(%q0, %q1), %s15 : (!jasp.Qubit, !jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState

    %s17 = jasp.quantum_gate "cp"(%q0, %q1, %f1), %s16 : (!jasp.Qubit, !jasp.Qubit, tensor<f64>), !jasp.QuantumState -> !jasp.QuantumState
    %s18 = jasp.quantum_gate "crz"(%q0, %q1, %f1), %s17 : (!jasp.Qubit, !jasp.Qubit, tensor<f64>), !jasp.QuantumState -> !jasp.QuantumState
    %s19 = jasp.quantum_gate "rxx"(%q0, %q1, %f1), %s18 : (!jasp.Qubit, !jasp.Qubit, tensor<f64>), !jasp.QuantumState -> !jasp.QuantumState
    %s20 = jasp.quantum_gate "rzz"(%q0, %q1, %f1), %s19 : (!jasp.Qubit, !jasp.Qubit, tensor<f64>), !jasp.QuantumState -> !jasp.QuantumState
    %s21 = jasp.quantum_gate "xxyy"(%q0, %q1, %f1, %f2), %s20 : (!jasp.Qubit, !jasp.Qubit, tensor<f64>, tensor<f64>), !jasp.QuantumState -> !jasp.QuantumState

    %s22 = jasp.quantum_gate "t_dg"(%q0), %s4 : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
    %s23 = jasp.quantum_gate "s_dg"(%q0), %s4 : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState

    %state_out = jasp.quantum_gate "gphase"(%f1), %s21 : (tensor<f64>), !jasp.QuantumState -> !jasp.QuantumState

    return
  }
}

// CHECK-LABEL:   @main
// CHECK-NOT:       !jasp.QuantumState
// CHECK-SAME:      [[Q0:%.+]]: !qc.qubit,
// CHECK-SAME:      [[Q1:%.+]]: !qc.qubit
// CHECK:           qc.x [[Q0]] : !qc.qubit
// CHECK:           qc.y [[Q0]] : !qc.qubit
// CHECK:           qc.z [[Q0]] : !qc.qubit
// CHECK:           qc.h [[Q0]] : !qc.qubit
// CHECK:           qc.s [[Q0]] : !qc.qubit
// CHECK:           qc.t [[Q0]] : !qc.qubit
// CHECK:           qc.sx [[Q0]] : !qc.qubit
// CHECK:           qc.id [[Q0]] : !qc.qubit
// CHECK:           qc.p({{.*}}) [[Q0]] : !qc.qubit
// CHECK:           qc.rx({{.*}}) [[Q0]] : !qc.qubit
// CHECK:           qc.ry({{.*}}) [[Q0]] : !qc.qubit
// CHECK:           qc.rz({{.*}}) [[Q0]] : !qc.qubit
// CHECK:           qc.u({{.*}}, {{.*}}, {{.*}}) [[Q0]] : !qc.qubit
// CHECK:           qc.ctrl([[Q0]]) {
// CHECK:             qc.x [[Q1]] : !qc.qubit
// CHECK:           } : !qc.qubit
// CHECK:           qc.ctrl([[Q0]]) {
// CHECK:             qc.y [[Q1]] : !qc.qubit
// CHECK:           } : !qc.qubit
// CHECK:           qc.ctrl([[Q0]]) {
// CHECK:             qc.z [[Q1]] : !qc.qubit
// CHECK:           } : !qc.qubit
// CHECK:           qc.swap [[Q0]], [[Q1]] : !qc.qubit, !qc.qubit
// CHECK:           qc.ctrl([[Q0]]) {
// CHECK:             qc.p({{.*}}) [[Q1]] : !qc.qubit
// CHECK:           } : !qc.qubit
// CHECK:           qc.ctrl([[Q0]]) {
// CHECK:             qc.rz({{.*}}) [[Q1]] : !qc.qubit
// CHECK:           } : !qc.qubit
// CHECK:           qc.rxx({{.*}}) [[Q0]], [[Q1]] : !qc.qubit, !qc.qubit
// CHECK:           qc.rzz({{.*}}) [[Q0]], [[Q1]] : !qc.qubit, !qc.qubit
// CHECK:           qc.xx_plus_yy({{.*}}, {{.*}}) [[Q0]], [[Q1]] : !qc.qubit, !qc.qubit
// CHECK:           qc.gphase({{.*}})
// CHECK:           return
// CHECK:         }
