// RUN: qcc %s --quantum-device=magic --device-description=%S/Inputs/device-2x3-500ns.mlir --compile-to=custom-magic -o %t.txt
// RUN: FileCheck %s < %t.txt
// RUN: magic-runner --file %t.txt --device %S/Inputs/device-2x3-500ns.mlir -s 3 | FileCheck %s --check-prefix=CHECK-SIM
// RUN: magic-runner --file %t.txt --device %S/Inputs/device-2x3-500ns.mlir --probabilities --keep-garbage-bits | FileCheck %s --check-prefix=CHECK-ALL-BITS

// The exporter on a program that is already magic IR. The driver completes it: the unmeasured ion 5 is measured and
// recorded as garbage, the ions 2, 5, 7 become 0, 1, 2, and trap 1 waits before the shuttle as long as trap 0 did.

!a  = !magic.ion_chain<0, [2:1, 5:1]>
!b  = !magic.ion_chain<1, [7:1]>
!as = !magic.ion_chain<0, [5:1]>
!bs = !magic.ion_chain<1, [2:1, 7:1]>

func.func @main() {
  %a0, %b0 = magic.init : !a, !b
  %a1 = magic.sym_zxz %a0 ions [2, 5] {z = [0.0, -0.25], x = [3.141592653589793, 0.5]} : !a
  %a2 = magic.delay %a1 {ticks = 2491} : !a
  %a3, %b1 = magic.shuttle %a2, %b0 : !a, !b -> !as, !bs
  %b2 = magic.sym_zxz %b1 ions [7] {z = [1.0], x = [3.141592653589793]} : !bs
  %m2, %m7 = magic.mzd %b2 : !bs -> i1, i1
  aux.record_int %m7 : i1
  aux.record_int %m2 : i1
  return
}

// The header: the traps of the device, the ions each trap holds initially, and for every ion the bit it is measured
// into. The garbage bits come last.
// CHECK:      OPENQASM 3.0;
// CHECK-NEXT: include "{{.+}}";
// CHECK-EMPTY:
// CHECK-NEXT: // The program is compiled for 2 ion traps with the following configuration:
// CHECK-NEXT: //     capacities (3, 3),
// CHECK-NEXT: //     occupancies (2, 1),
// CHECK-NEXT: //     ion-bit map [1, 2, 0],
// CHECK-NEXT: //     unused_qubits ().
// CHECK-NEXT: // Result bits of the program: the first 2 of c, the remaining bits are garbage.
// CHECK-EMPTY:
// CHECK-NEXT: creg c[3];
// CHECK-NEXT: qreg q[3];

// A symmetric rotation is always three lines, ion by ion. Numbers are plain decimals.
// CHECK-NEXT: rz(0) q[0];
// CHECK-NEXT: rx(3.141592653589793) q[0];
// CHECK-NEXT: rz(0) q[0];
// CHECK-NEXT: rz(-0.25) q[1];
// CHECK-NEXT: rx(0.5) q[1];
// CHECK-NEXT: rz(0.25) q[1];

// 2491 ticks of 0.5 us. A delay names all ions of its trap.
// CHECK-NEXT: delay[1245.5us] q[0],q[1];
// CHECK-NEXT: recode q[2];
// CHECK-NEXT: delay[1245.5us] q[2];
// CHECK-NEXT: recode q[2];
// CHECK-NEXT: shuttle(0,1) q[0];
// CHECK-NEXT: rz(1) q[2];
// CHECK-NEXT: rx(3.141592653589793) q[2];
// CHECK-NEXT: rz(-1) q[2];

// Every ion is measured, in ion order.
// CHECK-NEXT: c[1] = measure q[0];
// CHECK-NEXT: c[2] = measure q[1];
// CHECK-NEXT: c[0] = measure q[2];
// CHECK-EMPTY:

// The two recorded ions are flipped to |1>. The garbage bit is dropped by default.
// CHECK-SIM:      START
// CHECK-SIM-NEXT: METADATA required_num_qubits 3
// CHECK-SIM-NEXT: METADATA required_num_results 2
// CHECK-SIM-NEXT: OUTPUT INT 3
// CHECK-SIM-NEXT: END 0
// CHECK-SIM:      OUTPUT INT 3
// CHECK-SIM:      OUTPUT INT 3

// The garbage bit is the ion rotated by rx(0.5): it is |1> with probability sin^2(0.25).
// CHECK-ALL-BITS:      START
// CHECK-ALL-BITS-NEXT: METADATA required_num_qubits 3
// CHECK-ALL-BITS-NEXT: METADATA required_num_results 3
// CHECK-ALL-BITS-NEXT: PROBABILITY INT 3 0.938791
// CHECK-ALL-BITS-NEXT: PROBABILITY INT 7 0.061209
// CHECK-ALL-BITS-NEXT: END 0
