// RUN: qcc %s -o %t.ll
// RUN: FileCheck %s --check-prefix=CHECK-QIR < %t.ll
// RUN: qir-runner --file %t.ll -s 4 | FileCheck %s --check-prefix=CHECK-SIM

// The same program taken all the way to HiSEP-Q QISA, in builds that have that target.
// RUN: %if hisepq %{ qcc --target=hisepq --compile-to=native %s | FileCheck %s --check-prefix=CHECK-QISA %}

// GENERATED FROM QRISP VERSION 0.9.6

builtin.module @jasp_module {
  func.func public @main(%arg0: !jasp.QuantumState) -> (tensor<i64>, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState) {
    %0 = arith.constant dense<3> : tensor<i64>
    %1, %2 = "jasp.create_qubits"(%0, %arg0) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %3, %4 = "jasp.create_qubits"(%0, %2) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %5 = arith.constant dense<0> : tensor<i64>
    %6 = "jasp.get_qubit"(%1, %5) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %7 = "jasp.quantum_gate"(%6, %4) {gate_type = "h"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %8 = arith.constant dense<1> : tensor<i64>
    %9 = "jasp.get_qubit"(%1, %8) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %10 = "jasp.quantum_gate"(%6, %9, %7) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %11 = arith.constant dense<2> : tensor<i64>
    %12 = "jasp.get_qubit"(%1, %11) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %13 = "jasp.quantum_gate"(%6, %12, %10) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %14 = "jasp.quantum_gate"(%9, %13) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %15, %16 = "jasp.create_qubits"(%11, %14) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %17 = "jasp.get_qubit"(%15, %5) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %18 = "jasp.quantum_gate"(%6, %17, %16) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %19 = "jasp.quantum_gate"(%9, %17, %18) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %20 = "jasp.get_qubit"(%15, %8) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %21 = "jasp.quantum_gate"(%9, %20, %19) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %22 = "jasp.quantum_gate"(%12, %20, %21) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %23, %24 = "jasp.measure"(%15, %22) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
    %25 = "jasp.delete_qubits"(%15, %24) : (!jasp.QubitArray, !jasp.QuantumState) -> !jasp.QuantumState
    %26 = arith.constant 1 : i64
    %27 = tensor.extract %23[] : tensor<i64>
    %28 = arith.cmpi eq, %27, %26 : i64
    %29 = arith.constant true
    %30 = arith.xori %28, %29 : i1
    %31 = scf.if %30 -> (!jasp.QuantumState) {
      scf.yield %25 : !jasp.QuantumState
    } else {
      %32 = "jasp.quantum_gate"(%6, %25) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      scf.yield %32 : !jasp.QuantumState
    }
    %33 = arith.constant 3 : i64
    %34 = tensor.extract %23[] : tensor<i64>
    %35 = arith.cmpi eq, %34, %33 : i64
    %36 = arith.constant true
    %37 = arith.xori %35, %36 : i1
    %38 = scf.if %37 -> (!jasp.QuantumState) {
      scf.yield %31 : !jasp.QuantumState
    } else {
      %39 = "jasp.quantum_gate"(%9, %31) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      scf.yield %39 : !jasp.QuantumState
    }
    %40 = arith.constant 2 : i64
    %41 = tensor.extract %23[] : tensor<i64>
    %42 = arith.cmpi eq, %41, %40 : i64
    %43 = arith.constant true
    %44 = arith.xori %42, %43 : i1
    %45 = scf.if %44 -> (!jasp.QuantumState) {
      scf.yield %38 : !jasp.QuantumState
    } else {
      %46 = "jasp.quantum_gate"(%12, %38) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      scf.yield %46 : !jasp.QuantumState
    }
    %47, %48 = "jasp.create_qubits"(%11, %45) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %49 = "jasp.get_qubit"(%3, %5) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %50 = "jasp.get_qubit"(%47, %5) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %51 = "jasp.quantum_gate"(%49, %50, %48) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %52 = "jasp.get_qubit"(%3, %8) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %53 = "jasp.quantum_gate"(%52, %50, %51) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %54 = "jasp.get_qubit"(%47, %8) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %55 = "jasp.quantum_gate"(%52, %54, %53) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %56 = "jasp.get_qubit"(%3, %11) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %57 = "jasp.quantum_gate"(%56, %54, %55) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %58, %59 = "jasp.measure"(%47, %57) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
    %60 = "jasp.delete_qubits"(%47, %59) : (!jasp.QubitArray, !jasp.QuantumState) -> !jasp.QuantumState
    %61 = arith.constant 1 : i64
    %62 = tensor.extract %58[] : tensor<i64>
    %63 = arith.cmpi eq, %62, %61 : i64
    %64 = arith.constant true
    %65 = arith.xori %63, %64 : i1
    %66 = scf.if %65 -> (!jasp.QuantumState) {
      scf.yield %60 : !jasp.QuantumState
    } else {
      %67 = "jasp.quantum_gate"(%49, %60) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      scf.yield %67 : !jasp.QuantumState
    }
    %68 = arith.constant 3 : i64
    %69 = tensor.extract %58[] : tensor<i64>
    %70 = arith.cmpi eq, %69, %68 : i64
    %71 = arith.constant true
    %72 = arith.xori %70, %71 : i1
    %73 = scf.if %72 -> (!jasp.QuantumState) {
      scf.yield %66 : !jasp.QuantumState
    } else {
      %74 = "jasp.quantum_gate"(%52, %66) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      scf.yield %74 : !jasp.QuantumState
    }
    %75 = arith.constant 2 : i64
    %76 = tensor.extract %58[] : tensor<i64>
    %77 = arith.cmpi eq, %76, %75 : i64
    %78 = arith.constant true
    %79 = arith.xori %77, %78 : i1
    %80 = scf.if %79 -> (!jasp.QuantumState) {
      scf.yield %73 : !jasp.QuantumState
    } else {
      %81 = "jasp.quantum_gate"(%56, %73) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      scf.yield %81 : !jasp.QuantumState
    }
    %82 = "jasp.quantum_gate"(%6, %49, %80) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %83 = "jasp.quantum_gate"(%9, %52, %82) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %84 = "jasp.quantum_gate"(%12, %56, %83) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %85 = "jasp.quantum_gate"(%56, %84) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %86, %87 = "jasp.create_qubits"(%11, %85) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %88 = "jasp.get_qubit"(%86, %5) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %89 = "jasp.quantum_gate"(%6, %88, %87) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %90 = "jasp.quantum_gate"(%9, %88, %89) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %91 = "jasp.get_qubit"(%86, %8) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %92 = "jasp.quantum_gate"(%9, %91, %90) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %93 = "jasp.quantum_gate"(%12, %91, %92) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %94, %95 = "jasp.measure"(%86, %93) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
    %96 = "jasp.delete_qubits"(%86, %95) : (!jasp.QubitArray, !jasp.QuantumState) -> !jasp.QuantumState
    %97 = arith.constant 1 : i64
    %98 = tensor.extract %94[] : tensor<i64>
    %99 = arith.cmpi eq, %98, %97 : i64
    %100 = arith.constant true
    %101 = arith.xori %99, %100 : i1
    %102 = scf.if %101 -> (!jasp.QuantumState) {
      scf.yield %96 : !jasp.QuantumState
    } else {
      %103 = "jasp.quantum_gate"(%6, %96) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      scf.yield %103 : !jasp.QuantumState
    }
    %104 = arith.constant 3 : i64
    %105 = tensor.extract %94[] : tensor<i64>
    %106 = arith.cmpi eq, %105, %104 : i64
    %107 = arith.constant true
    %108 = arith.xori %106, %107 : i1
    %109 = scf.if %108 -> (!jasp.QuantumState) {
      scf.yield %102 : !jasp.QuantumState
    } else {
      %110 = "jasp.quantum_gate"(%9, %102) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      scf.yield %110 : !jasp.QuantumState
    }
    %111 = arith.constant 2 : i64
    %112 = tensor.extract %94[] : tensor<i64>
    %113 = arith.cmpi eq, %112, %111 : i64
    %114 = arith.constant true
    %115 = arith.xori %113, %114 : i1
    %116 = scf.if %115 -> (!jasp.QuantumState) {
      scf.yield %109 : !jasp.QuantumState
    } else {
      %117 = "jasp.quantum_gate"(%12, %109) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      scf.yield %117 : !jasp.QuantumState
    }
    %118, %119 = "jasp.create_qubits"(%11, %116) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
    %120 = "jasp.get_qubit"(%118, %5) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %121 = "jasp.quantum_gate"(%49, %120, %119) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %122 = "jasp.quantum_gate"(%52, %120, %121) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %123 = "jasp.get_qubit"(%118, %8) : (!jasp.QubitArray, tensor<i64>) -> !jasp.Qubit
    %124 = "jasp.quantum_gate"(%52, %123, %122) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %125 = "jasp.quantum_gate"(%56, %123, %124) {gate_type = "cx"} : (!jasp.Qubit, !jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
    %126, %127 = "jasp.measure"(%118, %125) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
    %128 = "jasp.delete_qubits"(%118, %127) : (!jasp.QubitArray, !jasp.QuantumState) -> !jasp.QuantumState
    %129 = arith.constant 1 : i64
    %130 = tensor.extract %126[] : tensor<i64>
    %131 = arith.cmpi eq, %130, %129 : i64
    %132 = arith.constant true
    %133 = arith.xori %131, %132 : i1
    %134 = scf.if %133 -> (!jasp.QuantumState) {
      scf.yield %128 : !jasp.QuantumState
    } else {
      %135 = "jasp.quantum_gate"(%49, %128) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      scf.yield %135 : !jasp.QuantumState
    }
    %136 = arith.constant 3 : i64
    %137 = tensor.extract %126[] : tensor<i64>
    %138 = arith.cmpi eq, %137, %136 : i64
    %139 = arith.constant true
    %140 = arith.xori %138, %139 : i1
    %141 = scf.if %140 -> (!jasp.QuantumState) {
      scf.yield %134 : !jasp.QuantumState
    } else {
      %142 = "jasp.quantum_gate"(%52, %134) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      scf.yield %142 : !jasp.QuantumState
    }
    %143 = arith.constant 2 : i64
    %144 = tensor.extract %126[] : tensor<i64>
    %145 = arith.cmpi eq, %144, %143 : i64
    %146 = arith.constant true
    %147 = arith.xori %145, %146 : i1
    %148 = scf.if %147 -> (!jasp.QuantumState) {
      scf.yield %141 : !jasp.QuantumState
    } else {
      %149 = "jasp.quantum_gate"(%56, %141) {gate_type = "x"} : (!jasp.Qubit, !jasp.QuantumState) -> !jasp.QuantumState
      scf.yield %149 : !jasp.QuantumState
    }
    %150, %151 = "jasp.measure"(%1, %148) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
    %152, %153 = "jasp.measure"(%3, %151) : (!jasp.QubitArray, !jasp.QuantumState) -> (tensor<i64>, !jasp.QuantumState)
    %154 = tensor.extract %150[] : tensor<i64>
    %155 = tensor.extract %152[] : tensor<i64>
    %156 = arith.xori %154, %155 : i64
    %157 = tensor.from_elements %156 : tensor<i64>
    func.return %150, %157, %23, %126, %153 : tensor<i64>, tensor<i64>, tensor<i64>, tensor<i64>, !jasp.QuantumState
  }
}

// A Bell state of two logical qubits of the 3-qubit repetition code (blocks 0-2 and 3-5), with a correction round
// on each block after every gate. The logical Hadamard is not transversal on this code, so the first block is encoded
// straight into logical |+>; the CNOT between the blocks is transversal.

// Encoding, and the injected error on data qubit 1.
// CHECK-QIR:      call void @__quantum__qis__h__body(ptr null)
// CHECK-QIR-NEXT: call void @__quantum__qis__cx__body(ptr null, ptr inttoptr (i64 1 to ptr))
// CHECK-QIR-NEXT: call void @__quantum__qis__cx__body(ptr null, ptr inttoptr (i64 2 to ptr))
// CHECK-QIR-NEXT: call void @__quantum__qis__x__body(ptr inttoptr (i64 1 to ptr))

// First round on block `a`, on ancillas 6 and 7, ends in the conditional corrections.
// CHECK-QIR:      call void @__quantum__qis__cx__body(ptr null, ptr inttoptr (i64 6 to ptr))
// CHECK-QIR:      call void @__quantum__qis__mz__body(ptr inttoptr (i64 7 to ptr), ptr inttoptr (i64 7 to ptr))
// CHECK-QIR:      br i1
// CHECK-QIR:      call void @__quantum__qis__x__body(ptr inttoptr (i64 1 to ptr))

// The transversal CNOT, one `cx` per pair of data qubits, after both blocks' first rounds.
// CHECK-QIR:      call void @__quantum__qis__cx__body(ptr null, ptr inttoptr (i64 3 to ptr))
// CHECK-QIR-NEXT: call void @__quantum__qis__cx__body(ptr inttoptr (i64 1 to ptr), ptr inttoptr (i64 4 to ptr))
// CHECK-QIR-NEXT: call void @__quantum__qis__cx__body(ptr inttoptr (i64 2 to ptr), ptr inttoptr (i64 5 to ptr))
// CHECK-QIR-NEXT: call void @__quantum__qis__x__body(ptr inttoptr (i64 5 to ptr))

// Four results.
// CHECK-QIR:      call void @__quantum__rt__tuple_record_output(i64 4

// Six data qubits plus two ancillas for each of the four rounds.
// CHECK-SIM:      METADATA required_num_qubits 14

// The first block reads out as |000> or |111> at random; the second one, being its Bell partner, reads out the same,
// so the XOR of the two is 0. The two injected errors show up in the syndromes of the rounds that corrected them.
// CHECK-SIM:      OUTPUT TUPLE 4
// CHECK-SIM-NEXT: OUTPUT INT {{[07]}}
// CHECK-SIM-NEXT: OUTPUT INT 0
// CHECK-SIM-NEXT: OUTPUT INT 3
// CHECK-SIM-NEXT: OUTPUT INT 2
// CHECK-SIM:      OUTPUT TUPLE 4
// CHECK-SIM-NEXT: OUTPUT INT {{[07]}}
// CHECK-SIM-NEXT: OUTPUT INT 0
// CHECK-SIM-NEXT: OUTPUT INT 3
// CHECK-SIM-NEXT: OUTPUT INT 2

// On HiSEP-Q the single Hadamard is the one of the encoding; everything else is `cx`, measurements and the
// conditional corrections.
//
// TODO: The transversal CNOT is three `qv.cx` rather than one over all three pairs. Its three qubit pairs sit at
// different depths after the encoding and the first round, and `qvec-merge` only merges within a depth.
// CHECK-QISA-LABEL: main:
// CHECK-QISA:         qv.h
// CHECK-QISA-NOT:     qv.h
// CHECK-QISA:         .Lfunc_end0:
