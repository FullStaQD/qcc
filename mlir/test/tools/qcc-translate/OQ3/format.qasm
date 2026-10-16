// RUN: split-file %s %t
// RUN: qcc-translate --import-openqasm %t/messy.qasm | qcc-translate --export-openqasm \
// RUN:   | FileCheck %s --strict-whitespace

// An import and export formats a program: the text of every statement and comment survives, but whitespace, redundant
// parentheses, digit separators, and the case of hexadecimal digits do not.

// CHECK: // header
// CHECK-NEXT: OPENQASM 3.1;
// CHECK-NEXT: include "stdgates.inc";
// CHECK-NEXT: qubit[2] q;
// CHECK-NEXT: rx(pi) q;
// CHECK-NEXT: rx(1 + 2 * 3) q;
// CHECK-NEXT: rx((1 + 2) * 3) q;
// CHECK-NEXT: rx(--pi) q;
// CHECK-NEXT: rx(1000 + 0xab) q;
// CHECK-NEXT: cx q[0], q[1];  // trailing
// CHECK-NEXT: /* moved */
// CHECK-NEXT: barrier q[0], q[1];
// CHECK-NEXT: pragma ns.name  inner  spaces  are  kept
// CHECK-NEXT: // end

//--- messy.qasm
// header
OPENQASM   3.1 ;
include   'stdgates.inc' ;
qubit [ 2 ]q;
rx(((pi)))q;
rx(1+(2*3)) q;
rx((1+2)*3) q;
rx(-(-pi)) q;
rx(1_000 + 0xAB) q;
cx q[0],q[1];// trailing
barrier q[0], /* moved */
  q[1];
pragma   ns.name  inner  spaces  are  kept
// end
