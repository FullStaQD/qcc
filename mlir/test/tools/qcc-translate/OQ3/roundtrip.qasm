// RUN: qcc-translate --split-input-file --output-split-marker="// =====" --import-openqasm --oq3-allow-dev-version %s \
// RUN:   | qcc-translate --split-input-file="// =====" --export-openqasm \
// RUN:   | FileCheck %s --strict-whitespace

// Programs in the canonical form of the export survive an import and export unchanged. The CHECK lines repeat each
// program; being comments, they are not part of it.

// CHECK:      OPENQASM 3.1;
// CHECK-NEXT: include "stdgates.inc";
// CHECK-NEXT: qubit[2] q;
// CHECK-NEXT: bit[2] c;
// CHECK-NEXT: h q[0];
// CHECK-NEXT: cx q[0], q[1];
// CHECK-NEXT: c = measure q;

OPENQASM 3.1;
include "stdgates.inc";
qubit[2] q;
bit[2] c;
h q[0];
cx q[0], q[1];
c = measure q;

// -----

// CHECK:      OPENQASM 3.0;
// CHECK-NEXT: include "stdgates.inc";
// CHECK-NEXT: qubit a;
// CHECK-NEXT: qubit[3] r;
// CHECK-NEXT: qubit[0] empty;
// CHECK-NEXT: bit b;
// CHECK-NEXT: bit[3] m;
// CHECK-NEXT: x a;
// CHECK-NEXT: h r;
// CHECK-NEXT: cx a, r[1];
// CHECK-NEXT: ccx r[0], r[-1], a;
// CHECK-NEXT: U(0, 0, pi) $2;
// CHECK-NEXT: gphase(pi / 4);
// CHECK-NEXT: reset r[0];
// CHECK-NEXT: reset r;
// CHECK-NEXT: barrier;
// CHECK-NEXT: barrier a, r, $0;
// CHECK-NEXT: b = measure a;
// CHECK-NEXT: m[2] = measure r[0];
// CHECK-NEXT: m = measure r;
// CHECK-NEXT: measure $1;
// CHECK-NEXT: bit c = measure $0;
// CHECK-NEXT: bit[3] d = measure r;

OPENQASM 3.0;
include "stdgates.inc";
qubit a;
qubit[3] r;
qubit[0] empty;
bit b;
bit[3] m;
x a;
h r;
cx a, r[1];
ccx r[0], r[-1], a;
U(0, 0, pi) $2;
gphase(pi / 4);
reset r[0];
reset r;
barrier;
barrier a, r, $0;
b = measure a;
m[2] = measure r[0];
m = measure r;
measure $1;
bit c = measure $0;
bit[3] d = measure r;

// -----

// CHECK:      OPENQASM 3.2;
// CHECK-NEXT: include "stdgates.inc";
// CHECK-NEXT: qubit q;
// CHECK-NEXT: rx(pi) q;
// CHECK-NEXT: rx(-pi) q;
// CHECK-NEXT: rx(tau / 2 - euler) q;
// CHECK-NEXT: rx(1 + 2 * 3) q;
// CHECK-NEXT: rx((1 + 2) * 3) q;
// CHECK-NEXT: rx(1 - (2 - 3)) q;
// CHECK-NEXT: rx(1 - 2 - 3) q;
// CHECK-NEXT: rx(8 / (4 / 2)) q;
// CHECK-NEXT: rx(-(1 + 2)) q;
// CHECK-NEXT: rx(--1) q;
// CHECK-NEXT: rx(1.5 + .5 + 2. + 1e3 + 2.5e-3) q;
// CHECK-NEXT: cu(1, 2, 3, 4) q, $0;
// CHECK-NEXT: bit b = 1;
// CHECK-NEXT: bit[4] bits = "0101";
// CHECK-NEXT: b = 0;
// CHECK-NEXT: bits = "1111";
// CHECK-NEXT: bits[0] = 1;
// CHECK-NEXT: bit copy = b;

OPENQASM 3.2;
include "stdgates.inc";
qubit q;
rx(pi) q;
rx(-pi) q;
rx(tau / 2 - euler) q;
rx(1 + 2 * 3) q;
rx((1 + 2) * 3) q;
rx(1 - (2 - 3)) q;
rx(1 - 2 - 3) q;
rx(8 / (4 / 2)) q;
rx(-(1 + 2)) q;
rx(--1) q;
rx(1.5 + .5 + 2. + 1e3 + 2.5e-3) q;
cu(1, 2, 3, 4) q, $0;
bit b = 1;
bit[4] bits = "0101";
b = 0;
bits = "1111";
bits[0] = 1;
bit copy = b;

// -----

// Pragmas and annotations are kept.
// CHECK:      OPENQASM 3.1;
// CHECK-NEXT: pragma qcc.simulator noise model "qpu1.noise"
// CHECK-NEXT: include "stdgates.inc";
// CHECK-NEXT: @ns.name
// CHECK-NEXT: @ns.with.args some text
// CHECK-NEXT: qubit q;
// CHECK-NEXT: h q;

OPENQASM 3.1;
pragma qcc.simulator noise model "qpu1.noise"
include "stdgates.inc";
@ns.name
@ns.with.args some text
qubit q;
h q;
