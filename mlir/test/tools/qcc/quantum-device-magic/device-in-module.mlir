// RUN: qcc %s --quantum-device=magic --compile-to=custom-magic | FileCheck %s
// RUN: not qcc %s --quantum-device=magic --device-description=%S/Inputs/device-2x3-500ns.mlir --compile-to=custom-magic 2>&1 | FileCheck %s --check-prefix=CHECK-ERR

// A module that carries its device needs no --device-description, and must not get a second one.

#trap = #magic.trap<capacity = 2, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 1200.0], [1200.0, 0.0]]> : tensor<2x2xf64>]>

module attributes {qcc.device = #magic.device<name = "one-trap", time_unit_ns = 1000, traps = [#trap]>} {
  func.func @main() {
    %q0 = qc.static 0 : !qc.qubit
    %q1 = qc.static 1 : !qc.qubit
    qc.x %q1 : !qc.qubit
    %m0 = qc.measure %q0 : !qc.qubit -> i1
    %m1 = qc.measure %q1 : !qc.qubit -> i1
    aux.record_int %m0 : i1
    aux.record_int %m1 : i1
    return
  }
}

// CHECK:      // The program is compiled for 1 ion traps with the following configuration:
// CHECK-NEXT: //     capacities (2),
// CHECK-NEXT: //     occupancies (2),
// CHECK-NEXT: //     ion-bit map [0, 1],
// CHECK-NEXT: //     unused_qubits ().
// CHECK:      rx(3.141592653589793) q[1];
// CHECK:      c[0] = measure q[0];
// CHECK-NEXT: c[1] = measure q[1];

// CHECK-ERR: error: module already carries a 'qcc.device' attribute
