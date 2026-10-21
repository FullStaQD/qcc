// RUN: qcc-translate --import-openqasm %s | qcc-opt --canonicalize --cse | FileCheck %s --check-prefix=CHECK-IR
// RUN: qcc-translate --import-openqasm %s | qcc-opt --canonicalize --cse | qcc-translate --export-openqasm \
// RUN:   | FileCheck %s --strict-whitespace

// Expressions are pure, so generic simplifications may merge or reorder them. The program stays intact, and the
// export prints each use of an expression in full.

// One index and one angle serve every use.
// CHECK-IR:      %[[Q0:.*]] = oq3.qubit_index
// CHECK-IR:      %[[ANGLE:.*]] = oq3.cast {{.*}} -> !qcc.angle
// CHECK-IR-NEXT: oq3.gate_call @rx(%[[ANGLE]] : !qcc.angle) [%[[Q0]] : !qcc.qubit_ref]
// CHECK-IR-NEXT: oq3.gate_call @ry(%[[ANGLE]] : !qcc.angle) [%[[Q0]] : !qcc.qubit_ref]
// CHECK-IR:      oq3.gate_call @cx [%[[Q0]],
// CHECK-IR:      oq3.measure %[[Q0]]

// CHECK:      OPENQASM 3.1;
// CHECK-NEXT: include "stdgates.inc";
// CHECK-NEXT: qubit[2] q;
// CHECK-NEXT: bit[2] c;
// CHECK-NEXT: rx(pi / 2) q[0];
// CHECK-NEXT: ry(pi / 2) q[0];
// CHECK-NEXT: cx q[0], $1;
// CHECK-NEXT: c[0] = measure q[0];

OPENQASM 3.1;
include "stdgates.inc";
qubit[2] q;
bit[2] c;
rx(pi / 2) q[0];
ry(pi / 2) q[0];
cx q[0], $1;
c[0] = measure q[0];
