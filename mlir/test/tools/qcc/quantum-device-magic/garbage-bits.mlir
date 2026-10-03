// RUN: qcc %s --quantum-device=magic --device-description=%S/Inputs/device-2x3-500ns.mlir --compile-to=mlir | FileCheck %s --check-prefix=CHECK-MLIR
// RUN: qcc %s --quantum-device=magic --device-description=%S/Inputs/device-2x3-500ns.mlir --compile-to=custom-magic -o %t.txt
// RUN: FileCheck %s --check-prefix=CHECK-TXT < %t.txt
// RUN: %if magic-runner %{ magic-runner --file %t.txt --device %S/Inputs/device-2x3-500ns.mlir -s 5 | FileCheck %s --check-prefix=CHECK-SIM %}
// RUN: %if magic-runner %{ magic-runner --file %t.txt --device %S/Inputs/device-2x3-500ns.mlir -s 5 --keep-garbage-bits | FileCheck %s --check-prefix=CHECK-ALL-BITS %}

// A program in the QC dialect that uses less than it allocates and records less than it uses: a Bell pair on the
// qubits 2 and 3 of which only qubit 2 is measured.
//
// Four qubits spread over both traps. The qubits 0 and 1 (trap 0) do nothing, so trap 0 is not loaded at all, and the
// remaining ions 2 and 3 are renumbered to 0 and 1. The device reports every ion, so the second ion of the pair is
// measured and recorded as well, as a garbage result.

func.func @main() {
  %q0 = qc.static 0 : !qc.qubit
  %q1 = qc.static 1 : !qc.qubit
  %q2 = qc.static 2 : !qc.qubit
  %q3 = qc.static 3 : !qc.qubit
  qc.h %q0 : !qc.qubit
  qc.h %q2 : !qc.qubit
  qc.ctrl(%q2) targets (%target = %q3) {
    qc.x %target : !qc.qubit
    qc.yield
  } : {!qc.qubit}, {!qc.qubit}
  %m2 = qc.measure %q2 : !qc.qubit -> i1
  aux.record_int %m2 : i1
  return
}

// CHECK-MLIR:      !chain = !magic.ion_chain<1, [0:1, 1:1]>
// CHECK-MLIR:      func.func @main()
// CHECK-MLIR-NEXT:   magic.init : !chain
// CHECK-MLIR:        %[[M:.*]]:2 = magic.mzd %{{.*}} : !chain -> i1, i1
// CHECK-MLIR-NEXT:   aux.record_int %[[M]]#0 : i1
// CHECK-MLIR-NEXT:   aux.record_int %[[M]]#1 {magic.garbage_result} : i1
// CHECK-MLIR-NEXT:   return

// CHECK-TXT:      //     capacities (3, 3),
// CHECK-TXT-NEXT: //     occupancies (0, 2),
// CHECK-TXT-NEXT: //     ion-bit map [0, 1],
// CHECK-TXT-NEXT: //     unused_qubits ().
// CHECK-TXT-NEXT: // Result bits of the program: the first 1 of c, the remaining bits are garbage.
// CHECK-TXT-EMPTY:
// CHECK-TXT-NEXT: creg c[2];
// CHECK-TXT-NEXT: qreg q[2];
// CHECK-TXT:      delay[{{[0-9.]+}}us] q[0],q[1];
// CHECK-TXT:      c[0] = measure q[0];
// CHECK-TXT-NEXT: c[1] = measure q[1];

// One result bit, 0 or 1.
// CHECK-SIM:      METADATA required_num_results 1
// CHECK-SIM-NEXT: OUTPUT INT {{[01]}}
// CHECK-SIM-NOT:  OUTPUT INT {{[^01]}}

// With the garbage bit the correlation of the pair shows: 0 (|00>) or 3 (|11>).
// CHECK-ALL-BITS:      METADATA required_num_results 2
// CHECK-ALL-BITS-NEXT: OUTPUT INT {{[03]}}
// CHECK-ALL-BITS-NOT:  OUTPUT INT {{[^03]}}
