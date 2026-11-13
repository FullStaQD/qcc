// RUN: qcc-translate --export-custom-magic %s -o %t.txt
// RUN: FileCheck %s < %t.txt
// RUN: magic-runner --file %t.txt --device %s -s 3 | FileCheck %s --check-prefix=CHECK-SIM
// RUN: magic-runner --file %t.txt --device %s --probabilities --keep-garbage-bits | FileCheck %s --check-prefix=CHECK-ALL-BITS

// A finished program, as the MAGIC pipeline leaves it: the ions are numbered 0..N-1 trap by trap, every ion is measured
// and recorded (ion 1 as garbage), and trap 1 waits as long as trap 0 before the shuttle.

#trap = #magic.trap<capacity = 3, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 1200.0],
         [1200.0, 0.0]]> : tensor<2x2xf64>,
  dense<[[0.0, 1200.0, 900.0],
         [1200.0, 0.0, 1200.0],
         [900.0, 1200.0, 0.0]]> : tensor<3x3xf64>]>

!a = !magic.ion_chain<0, [0:1, 1:1]>
!b = !magic.ion_chain<1, [2:1]>
!bOff = !magic.ion_chain<1, [2:0]>
!as = !magic.ion_chain<0, [1:1]>
!bs = !magic.ion_chain<1, [0:1, 2:1]>

module attributes {qcc.device = #magic.device<name = "two-trap-2x3", time_unit_ns = 500, traps = [#trap, #trap]>} {
  func.func @main() attributes {qcc.entry_point} {
    %a0, %b0 = magic.init : !a, !b
    %a1 = magic.sym_zxz %a0 ions [0, 1] {z = [0.0, -0.25], x = [3.141592653589793, 0.5]} : !a
    %a2 = magic.delay %a1 {ticks = 2491} : !a
    %b1 = magic.recode %b0 : !b -> !bOff
    %b2 = magic.delay %b1 {ticks = 2491} : !bOff
    %b3 = magic.recode %b2 : !bOff -> !b
    %a3, %b4 = magic.shuttle %a2, %b3 : !a, !b -> !as, !bs
    %b5 = magic.sym_zxz %b4 ions [2] {z = [1.0], x = [3.141592653589793]} : !bs
    %m0, %m2 = magic.mzd %b5 : !bs -> i1, i1
    %m1 = magic.mzd %a3 : !as -> i1
    aux.record_int %m2 : i1
    aux.record_int %m0 : i1
    aux.record_int %m1 {magic.garbage_result} : i1
    return
  }

  // Only the entry point is exported. Any other function is ignored.
  func.func @unused() {
    %b0 = magic.init : !b
    %m2 = magic.mzd %b0 : !b -> i1
    aux.record_int %m2 : i1
    return
  }
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
// CHECK-NEXT: // qcc: result_bits = 2
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
