// RUN: qcc %s -o %t.ll
// RUN: FileCheck %s --check-prefix=CHECK-QIR < %t.ll
// RUN: qir-runner --file %t.ll -s 5 | FileCheck %s --check-prefix=CHECK-SIM

// GENERATED FROM QRISP VERSION 0.9.6

builtin.module @jasp_module {
  func.func public @main(%arg0: !jasp.QuantumState) -> (tensor<i64>, tensor<i64>, !jasp.QuantumState) {
    %0 = arith.constant dense<1> : tensor<i64>
    %1 = arith.constant dense<2> : tensor<i64>
    func.return %0, %1, %arg0 : tensor<i64>, tensor<i64>, !jasp.QuantumState
  }
}

//CHECK-QIR-LABEL:    define void @main() #0 {
//CHECK-QIR:        call void @__quantum__rt__initialize(ptr null)
//CHECK-QIR:        call void @__quantum__rt__tuple_record_output(i64 2, ptr @.qir_dummy_label)
//CHECK-QIR:        call void @__quantum__rt__int_record_output(i64 1, ptr @.qir_dummy_label)
//CHECK-QIR:        call void @__quantum__rt__int_record_output(i64 2, ptr @.qir_dummy_label)
//CHECK-QIR:        ret void
//CHECK-QIR:    }

//CHECK-SIM:   START
//CHECK-SIM:   METADATA    entry_point
//CHECK-SIM:   METADATA    output_labeling_schema  schema_id
//CHECK-SIM:   METADATA    qir_profiles    adaptive_profile
//CHECK-SIM:   METADATA    required_num_qubits     0
//CHECK-SIM:   METADATA    required_num_results    0
//CHECK-SIM:   OUTPUT      TUPLE   2       dummy_label
//CHECK-SIM:   OUTPUT      INT     1       dummy_label
//CHECK-SIM:   OUTPUT      INT     2       dummy_label
