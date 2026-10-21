// RUN: qcc-translate --import-openqasm %s | qcc-translate --export-openqasm | FileCheck %s --strict-whitespace

// CHECK:      OPENQASM 3.1;
// CHECK-NEXT: include "stdgates.inc";
// CHECK-NEXT: qubit[2] q;
// CHECK-NEXT: bit[2] c;
// CHECK-NEXT: reset q;
// CHECK-NEXT: h q[0];
// CHECK-NEXT: barrier q;
// CHECK-NEXT: cz q[0], q[1];
// CHECK-NEXT: barrier q;
// CHECK-NEXT: s q[0];
// CHECK-NEXT: cz q[0], q[1];
// CHECK-NEXT: barrier q;
// CHECK-NEXT: s q[0];
// CHECK-NEXT: z q[0];
// CHECK-NEXT: h q[0];
// CHECK-NEXT: barrier q;
// CHECK-NEXT: c = measure q;

// One randomized benchmarking sequence
include "stdgates.inc";

qubit[2] q;
bit[2] c;

reset q;
h q[0];
barrier q;
cz q[0], q[1];
barrier q;
s q[0];
cz q[0], q[1];
barrier q;
s q[0];
z q[0];
h q[0];
barrier q;
measure q -> c;
