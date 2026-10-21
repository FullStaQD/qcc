// RUN: qcc-translate --import-openqasm %s | qcc-opt --canonicalize --cse | FileCheck %s --check-prefix=CHECK-IR

OPENQASM 3.1;
include "stdgates.inc";
qubit[2] q;
bit[2] c;
rx(pi / 2) q[0];
ry(pi / 2) q[0];
cx q[0], $1;
c[0] = measure q[0];

// Only one index and one angle value.
// CHECK-IR:      %[[Q0:.*]] = oq3.qubit_index
// CHECK-IR:      %[[ANGLE:.*]] = oq3.cast {{.*}} -> !qcc.angle
// CHECK-IR-NEXT: oq3.gate_call @rx(%[[ANGLE]] : !qcc.angle) [%[[Q0]] : !qcc.qubit_ref]
// CHECK-IR-NEXT: oq3.gate_call @ry(%[[ANGLE]] : !qcc.angle) [%[[Q0]] : !qcc.qubit_ref]
// CHECK-IR:      oq3.gate_call @cx [%[[Q0]],
// CHECK-IR:      oq3.measure %[[Q0]]
