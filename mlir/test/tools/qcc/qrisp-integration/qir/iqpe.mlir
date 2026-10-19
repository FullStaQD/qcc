// RUN: qcc %s -o %t.ll
// RUN: FileCheck %s --check-prefix=CHECK-QIR < %t.ll
// qir-runner links against an older LLVM that cannot parse the `f0x...` floating-point literal syntax LLVM 23 now emits
// in textual IR (see https://github.com/llvm/llvm-project/pull/190649), so feed it bitcode instead, which is
// unaffected. TODO: revert back to text once qir-runner fixes this.
// RUN: qcc %s -o %t.bc --binary
// RUN: qir-runner --file %t.bc -s 5 | FileCheck %s --check-prefix=CHECK-SIM

// GENERATED FROM QRISP VERSION 0.9.6

builtin.module @jasp_module {
  func.func public @main(%arg2: !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState) {
    %0 = arith.constant dense<1> : tensor<i64>
    %1, %2 = "jasp.create_qubits"(%0, %arg2) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %3 = arith.constant dense<0> : tensor<i64>
    %4 = "jasp.get_qubit"(%1, %3) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %5 = "jasp.quantum_gate"(%4, %2) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %6, %7 = "jasp.create_qubits"(%0, %5) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %8 = arith.constant dense<3.125000e-01> : tensor<f64>
    %9 = arith.constant dense<4> : tensor<i64>
    %10, %11, %12, %13, %14, %15, %16, %17 = scf.while (%arg91 = %6, %arg92 = %8, %arg93 = %1, %arg94 = %9, %arg95 = %3, %arg96 = %3, %arg97 = %9, %arg98 = %7) : (!jasp.QubitArray, tensor<f64>, !jasp.QubitArray, tensor<i64>, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, tensor<f64>, !jasp.QubitArray, tensor<i64>, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState) {
      %18 = tensor.extract %arg96[] : tensor<i64>
      %19 = tensor.extract %arg97[] : tensor<i64>
      %20 = arith.cmpi slt, %18, %19 : i64
      scf.condition(%20) %arg91, %arg92, %arg93, %arg94, %arg95, %arg96, %arg97, %arg98 : !jasp.QubitArray, tensor<f64>, !jasp.QubitArray, tensor<i64>, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState
    } do {
    ^bb0(%arg3: !jasp.QubitArray, %arg4: tensor<f64>, %arg5: !jasp.QubitArray, %arg6: tensor<i64>, %arg7: tensor<i64>, %arg8: tensor<i64>, %arg9: tensor<i64>, %arg10: !jasp.QuantumState):
      %21 = arith.constant dense<0> : tensor<i64>
      %22 = "jasp.get_qubit"(%arg3, %21) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %23 = "jasp.reset"(%22, %arg10) : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %24 = "jasp.quantum_gate"(%22, %23) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %25 = arith.constant 3.1415926535897931 : f64
      %26 = tensor.extract %arg4[] : tensor<f64>
      %27 = arith.mulf %25, %26 : f64
      %28 = tensor.extract %arg6[] : tensor<i64>
      %29 = tensor.extract %arg8[] : tensor<i64>
      %30 = arith.subi %28, %29 : i64
      %31 = arith.sitofp %30 : i64 to f64
      %32 = arith.constant 2.000000e+00 : f64
      %33 = math.powf %32, %31 : f64
      %34 = arith.mulf %27, %33 : f64
      %35 = "jasp.get_qubit"(%arg5, %21) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
      %36 = arith.constant 5.000000e-01 : f64
      %37 = arith.mulf %36, %34 : f64
      %38 = tensor.from_elements %37 : tensor<f64>
      %39 = "jasp.quantum_gate"(%35, %38, %24) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
      %40 = arith.constant 5.000000e-01 : f64
      %41 = arith.mulf %40, %34 : f64
      %42 = tensor.from_elements %41 : tensor<f64>
      %43 = "jasp.quantum_gate"(%22, %42, %39) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
      %44 = "jasp.quantum_gate"(%22, %35, %43) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %45 = arith.constant -5.000000e-01 : f64
      %46 = arith.mulf %45, %34 : f64
      %47 = tensor.from_elements %46 : tensor<f64>
      %48 = "jasp.quantum_gate"(%35, %47, %44) {gate_type = "p"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
      %49 = "jasp.quantum_gate"(%22, %35, %48) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %50 = tensor.extract %arg8[] : tensor<i64>
      %51 = arith.constant 1 : i64
      %52 = arith.subi %50, %51 : i64
      %53 = tensor.from_elements %52 : tensor<i64>
      %54 = arith.subi %52, %52 : i64
      %55 = tensor.from_elements %54 : tensor<i64>
      %56, %57, %58, %59, %60, %61 = scf.while (%arg55 = %arg7, %arg56 = %arg8, %arg57 = %arg3, %arg58 = %53, %arg59 = %55, %arg60 = %49) : (tensor<i64>, tensor<i64>, !jasp.QubitArray, tensor<i64>, tensor<i64>, !jasp.QuantumState) -> (tensor<i64>, tensor<i64>, !jasp.QubitArray, tensor<i64>, tensor<i64>, !jasp.QuantumState) {
        %62 = tensor.extract %arg59[] : tensor<i64>
        %63 = tensor.extract %arg58[] : tensor<i64>
        %64 = arith.cmpi sle, %62, %63 : i64
        scf.condition(%64) %arg55, %arg56, %arg57, %arg58, %arg59, %arg60 : tensor<i64>, tensor<i64>, !jasp.QubitArray, tensor<i64>, tensor<i64>, !jasp.QuantumState
      } do {
      ^bb1(%arg23: tensor<i64>, %arg24: tensor<i64>, %arg25: !jasp.QubitArray, %arg26: tensor<i64>, %arg27: tensor<i64>, %arg28: !jasp.QuantumState):
        %65 = tensor.extract %arg23[] : tensor<i64>
        %66 = tensor.extract %arg27[] : tensor<i64>
        %67 = arith.constant 63 : i64
        %68 = arith.shrsi %65, %67 : i64
        %69 = arith.shrsi %65, %66 : i64
        %70 = arith.constant 64 : i64
        %71 = arith.cmpi ugt, %70, %66 : i64
        %72 = arith.select %71, %69, %68 : i64
        %73 = arith.constant 1 : i64
        %74 = arith.andi %72, %73 : i64
        %75 = arith.constant 1 : i64
        %76 = arith.cmpi eq, %74, %75 : i64
        %77 = arith.constant true
        %78 = arith.xori %76, %77 : i1
        %79 = scf.if %78 -> (!jasp.QuantumState) {
          scf.yield %arg28 : !jasp.QuantumState
        } else {
          %80 = tensor.extract %arg24[] : tensor<i64>
          %81 = tensor.extract %arg27[] : tensor<i64>
          %82 = arith.subi %81, %80 : i64
          %83 = arith.sitofp %82 : i64 to f64
          %84 = arith.constant 2.000000e+00 : f64
          %85 = math.powf %84, %83 : f64
          %86 = arith.constant -3.1415926535897931 : f64
          %87 = arith.mulf %86, %85 : f64
          %88 = tensor.from_elements %87 : tensor<f64>
          %89 = arith.constant dense<0> : tensor<i64>
          %90 = "jasp.get_qubit"(%arg25, %89) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
          %91 = "jasp.quantum_gate"(%90, %88, %arg28) {gate_type = "rz"} : (!jasp.Qubit, tensor<f64>, !jasp.QuantumState) -> !jasp.QuantumState
          scf.yield %91 : !jasp.QuantumState
        }
        %92 = arith.constant 1 : i64
        %93 = tensor.extract %arg27[] : tensor<i64>
        %94 = arith.addi %93, %92 : i64
        %95 = tensor.from_elements %94 : tensor<i64>
        %96 = func.call @_jrange_marker(%95, %arg26) : (tensor<i64>, tensor<i64>) -> tensor<i64>
        scf.yield %arg23, %arg24, %arg25, %arg26, %96, %79 : tensor<i64>, tensor<i64>, !jasp.QubitArray, tensor<i64>, tensor<i64>, !jasp.QuantumState
      }
      %97 = "jasp.quantum_gate"(%22, %61) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      %98, %99 = "jasp.measure"(%arg3, %97) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
      %100 = tensor.extract %arg8[] : tensor<i64>
      %101 = tensor.extract %98[] : tensor<i64>
      %102 = arith.constant 0 : i64
      %103 = arith.shli %101, %100 : i64
      %104 = arith.constant 64 : i64
      %105 = arith.cmpi ugt, %104, %100 : i64
      %106 = arith.select %105, %103, %102 : i64
      %107 = tensor.extract %arg7[] : tensor<i64>
      %108 = arith.ori %107, %106 : i64
      %109 = tensor.from_elements %108 : tensor<i64>
      %110 = arith.constant 1 : i64
      %111 = tensor.extract %arg8[] : tensor<i64>
      %112 = arith.addi %111, %110 : i64
      %113 = tensor.from_elements %112 : tensor<i64>
      scf.yield %arg3, %arg4, %arg5, %arg6, %109, %113, %arg9, %99 : !jasp.QubitArray, tensor<f64>, !jasp.QubitArray, tensor<i64>, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState
    }
    func.return %14, %17 : tensor<i64>, !jasp.QuantumState
  }
  func.func private @_jrange_marker(%arg0: tensor<i64>, %arg1: tensor<i64>) -> (tensor<i64>) {
    func.return %arg0 : tensor<i64>
  }
}

// At precision 4, we expect four measurements of the same auxiliary qubit 1.
// CHECK-QIR: call void @__quantum__qis__mz__body(ptr inttoptr (i64 1 to ptr), ptr inttoptr (i64 1 to ptr))
// CHECK-QIR: call void @__quantum__qis__mz__body(ptr inttoptr (i64 1 to ptr), ptr inttoptr (i64 1 to ptr))
// CHECK-QIR: call void @__quantum__qis__mz__body(ptr inttoptr (i64 1 to ptr), ptr inttoptr (i64 1 to ptr))
// CHECK-QIR: call void @__quantum__qis__mz__body(ptr inttoptr (i64 1 to ptr), ptr inttoptr (i64 1 to ptr))
// CHECK-QIR-NOT: call void @__quantum__qis__mz__body


// CHECK-SIM: START
// CHECK-SIM: METADATA required_num_qubits 2
// CHECK-SIM: METADATA required_num_results 2
// Expected output phase is 0.3125, in binary 0.0101, encoded as integer 0b 0101 = 5.
// CHECK-SIM: OUTPUT INT 5 dummy_label
// CHECK-SIM: OUTPUT INT 5 dummy_label
// CHECK-SIM: OUTPUT INT 5 dummy_label
// CHECK-SIM: OUTPUT INT 5 dummy_label
// CHECK-SIM: OUTPUT INT 5 dummy_label
// CHECK-SIM: END 0
