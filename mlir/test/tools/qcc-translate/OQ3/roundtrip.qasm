// RUN: split-file %s %t
// RUN: qcc-translate --import-openqasm %t/bell.qasm | qcc-translate --export-openqasm | diff %t/bell.qasm -
// RUN: qcc-translate --import-openqasm %t/quantum.qasm | qcc-translate --export-openqasm | diff %t/quantum.qasm -
// RUN: qcc-translate --import-openqasm %t/expressions.qasm | qcc-translate --export-openqasm \
// RUN:   | diff %t/expressions.qasm -
// RUN: qcc-translate --import-openqasm %t/directives.qasm | qcc-translate --export-openqasm \
// RUN:   | diff %t/directives.qasm -
// RUN: qcc-translate --import-openqasm %t/legacy.qasm 2>/dev/null | qcc-translate --export-openqasm \
// RUN:   | diff %t/legacy.qasm -
// RUN: qcc-translate --import-openqasm %t/no-version.qasm | qcc-translate --export-openqasm \
// RUN:   | diff %t/no-version.qasm -

// OpenQASM programs in the exporter's format survive an import and export unchanged.

//--- bell.qasm
// Prepare a Bell pair
OPENQASM 3.1;
include "stdgates.inc";
qubit[2] q;  // data qubits
bit[2] c;
h q[0];
cx q[0], q[1];
c = measure q;
//--- quantum.qasm
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
measure r -> m;
measure r[1] -> m[0];
measure $1;
bit c = measure $0;
bit[3] d = measure r;
//--- expressions.qasm
OPENQASM 3.2;
include "stdgates.inc";
qubit q;
rx(pi) q;
rx(-π) q;
rx(tau / 2 - euler) q;
rx(τ + ℯ) q;
rx(1 + 2 * 3) q;
rx((1 + 2) * 3) q;
rx(1 - (2 - 3)) q;
rx(1 - 2 - 3) q;
rx(8 / (4 / 2)) q;
rx(-(1 + 2)) q;
rx(--1) q;
rx(0x1f + 0b101 + 0o17 + 42) q;
rx(1.5 + .5 + 2. + 1e3 + 2.5e-3) q;
cu(1, 2, 3, 4) q, $0;
bit b = 1;
bit[4] bits = "0101";
b = 0;
bits = "1111";
bits[0] = 1;
bit copy = b;
//--- directives.qasm
/* A header
   block comment */
// and a line comment
OPENQASM 3.1;
pragma qcc.simulator noise model "qpu1.noise"
#pragma legacy.spelling
include "stdgates.inc";
// A standalone comment
/* and a block comment */
@ns.name
@ns.with.args some text
qubit q;  // trailing
h q;  /* trailing block */
x q;  /* two */ // trailing comments
// The end.
//--- legacy.qasm
OPENQASM 3;
include "stdgates.inc";
qreg q[2];
qreg single;
creg c[2];
creg flag;
h q;
c = measure q;
flag = measure single;
//--- no-version.qasm
qubit q;
U(1, 2, 3) q;
