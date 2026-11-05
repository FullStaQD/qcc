// RUN: qcc-translate --split-input-file --output-split-marker="// =====" --import-openqasm %s 2>/dev/null \
// RUN:   | qcc-translate --split-input-file="// =====" --export-openqasm \
// RUN:   | FileCheck %s --strict-whitespace

// An import and export normalizes a program: the export prints its canonical form. Comments, whitespace, redundant
// parentheses, digit separators, and alternative spellings are not kept.

// CHECK:      OPENQASM 3.1;
// CHECK-NEXT: include "stdgates.inc";
// CHECK-NEXT: qubit[2] q;
// CHECK-NEXT: rx(pi) q;
// CHECK-NEXT: rx(1 + 2 * 3) q;
// CHECK-NEXT: rx((1 + 2) * 3) q;
// CHECK-NEXT: rx(--pi) q;
// CHECK-NEXT: rx(1000 + 1.5) q;
// CHECK-NEXT: cx q[0], q[1];
// CHECK-NEXT: barrier q[0], q[1];
// CHECK-NEXT: pragma ns.name  inner  spaces  are  kept

/* A header
   comment */
OPENQASM   3.1 ;
include   'stdgates.inc' ;
qubit [ 2 ]q;
rx(((pi)))q;
rx(1+(2*3)) q;
rx((1+2)*3) q;
rx(-(-pi)) q;
rx(1_000 + 1.5) q;
cx q[0],q[1];// trailing
barrier q[0], /* inside */
  q[1];
pragma   ns.name  inner  spaces  are  kept
// The end.

// -----

// `OPENQASM 3;` is 3.0.
// CHECK:      OPENQASM 3.0;
// CHECK-NEXT: include "stdgates.inc";
// CHECK-NEXT: qubit[2] q;
// CHECK-NEXT: qubit single;
// CHECK-NEXT: bit[2] c;
// CHECK-NEXT: bit flag;
// CHECK-NEXT: rx(pi + tau + euler) q;
// CHECK-NEXT: rx(31 + 31 + 5 + 15) q;
// CHECK-NEXT: c = measure q;
// CHECK-NEXT: flag = measure single;
// CHECK-NEXT: pragma legacy.spelling

OPENQASM 3;
include "stdgates.inc";
qreg q[2];
qreg single;
creg c[2];
creg flag;
rx(π + τ + ℯ) q;
rx(0x1F + 0x1f + 0b101 + 0o17) q;
measure q -> c;
measure single -> flag;
#pragma legacy.spelling

// -----

// A program without a version line gets the default version.
// CHECK:      OPENQASM 3.1;
// CHECK-NEXT: qubit q;
// CHECK-NEXT: U(1, 2, 3) q;

qubit q;
U(1, 2, 3) q;
