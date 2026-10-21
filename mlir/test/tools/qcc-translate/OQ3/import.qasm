// RUN: split-file %s %t
// RUN: qcc-translate --import-openqasm %t/program.qasm | FileCheck %s --check-prefix=PROGRAM
// RUN: qcc-translate --import-openqasm %t/expressions.qasm | FileCheck %s --check-prefix=EXPR
// RUN: qcc-translate --import-openqasm %t/comments.qasm | FileCheck %s --check-prefix=COMMENTS
// RUN: qcc-translate --import-openqasm %t/legacy.qasm 2>&1 | FileCheck %s --check-prefix=LEGACY
// RUN: qcc-translate --import-openqasm %t/legacy.qasm 2>/dev/null | FileCheck %s --check-prefix=LEGACY-IR

// The IR that the importer builds.

// PROGRAM:      module attributes {oq3.version = #oq3.version<3, 1>} {
// PROGRAM-NEXT:   func.func @main() attributes {qcc.entry_point} {
// PROGRAM-NEXT:     oq3.include "stdgates.inc" id 0
// PROGRAM-NEXT:     %[[TWO:.*]] = oq3.constant #oq3.int<2> : !oq3.int
// PROGRAM-NEXT:     %[[Q:.*]] = oq3.qubit_decl "q" [%[[TWO]] : !oq3.int] : !oq3.qreg<2>
// PROGRAM-NEXT:     %[[C:.*]] = oq3.declare "c" : !qcc.ref<!oq3.bit>
// PROGRAM-NEXT:     oq3.gate_call @h [%[[Q]] : !oq3.qreg<2>]
// PROGRAM-NEXT:     %[[ZERO:.*]] = oq3.constant #oq3.int<0> : !oq3.int
// PROGRAM-NEXT:     %[[Q0:.*]] = oq3.qubit_index %[[Q]][%[[ZERO]]] : !oq3.qreg<2>, !oq3.int
// PROGRAM-NEXT:     %[[P1:.*]] = oq3.physical_qubit 1 : !qcc.qubit_ref
// PROGRAM-NEXT:     oq3.gate_call @cx [%[[Q0]], %[[P1]] : !qcc.qubit_ref, !qcc.qubit_ref]
// PROGRAM-NEXT:     %[[PI:.*]] = oq3.math_constant pi : !oq3.float
// PROGRAM-NEXT:     %[[ANGLE:.*]] = oq3.cast %[[PI]] implicit : !oq3.float -> !qcc.angle
// PROGRAM-NEXT:     oq3.gate_call @rz(%[[ANGLE]] : !qcc.angle) [%[[Q]] : !oq3.qreg<2>]
// Every use of `q[0]` indexes anew, as the source does.
// PROGRAM-NEXT:     %[[ZERO_AGAIN:.*]] = oq3.constant #oq3.int<0> : !oq3.int
// PROGRAM-NEXT:     %[[Q0_AGAIN:.*]] = oq3.qubit_index %[[Q]][%[[ZERO_AGAIN]]] : !oq3.qreg<2>, !oq3.int
// PROGRAM-NEXT:     %[[M:.*]] = oq3.measure %[[Q0_AGAIN]] : !qcc.qubit_ref -> !oq3.bit
// PROGRAM-NEXT:     qcc.ref.store %[[M]], %[[C]] {oq3.arrow} : !qcc.ref<!oq3.bit>
// PROGRAM-NEXT:     oq3.measure %[[Q]] : !oq3.qreg<2> -> !oq3.bits<2>
// PROGRAM-NEXT:     oq3.reset %[[Q]] : !oq3.qreg<2>
// PROGRAM-NEXT:     oq3.barrier{{$}}
// PROGRAM-NEXT:     return
// PROGRAM-NEXT:   }
// PROGRAM-NEXT: }

// No version line: the default version, which is not exported.
// EXPR:      module attributes {oq3.version = #oq3.version<3, 1, implicit>}

// EXPR:      %[[HEX:.*]] = oq3.constant #oq3.int<31> : !oq3.int radix hex
// EXPR-NEXT: %[[HEX_F:.*]] = oq3.cast %[[HEX]] implicit : !oq3.int -> !oq3.float
// EXPR-NEXT: %[[HEX_A:.*]] = oq3.cast %[[HEX_F]] implicit : !oq3.float -> !qcc.angle
// EXPR-NEXT: oq3.gate_call @rx(%[[HEX_A]] : !qcc.angle)

// EXPR:      oq3.constant #oq3.float<"1000.5e-3"> : !oq3.float

// EXPR:      %[[TWO:.*]] = oq3.constant #oq3.int<2> : !oq3.int
// EXPR-NEXT: %[[NEG:.*]] = oq3.unary neg %[[TWO]] : !oq3.int
// EXPR-NEXT: %[[PI:.*]] = oq3.math_constant pi : !oq3.float
// EXPR-NEXT: %[[NEG_F:.*]] = oq3.cast %[[NEG]] implicit : !oq3.int -> !oq3.float
// EXPR-NEXT: %[[PROD:.*]] = oq3.binary mul %[[NEG_F]], %[[PI]] : !oq3.float
// EXPR-NEXT: oq3.cast %[[PROD]] implicit : !oq3.float -> !qcc.angle

// EXPR:      %[[BITS:.*]] = oq3.constant #oq3.bitstring<"0101"> : !oq3.bits<4>
// EXPR-NEXT: %[[B:.*]] = oq3.declare "b" [%{{.*}} : !oq3.int] = %[[BITS]] : !oq3.bits<4> : !qcc.ref<!oq3.bits<4>>
// EXPR-NEXT: %[[ONE:.*]] = oq3.constant #oq3.int<1> : !oq3.int
// EXPR-NEXT: %[[ONE_BIT:.*]] = oq3.cast %[[ONE]] implicit : !oq3.int -> !oq3.bit
// EXPR-NEXT: oq3.declare "c" = %[[ONE_BIT]] : !oq3.bit : !qcc.ref<!oq3.bit>

// COMMENTS:      oq3.comment "/* before the\0A   version line */" header
// COMMENTS-NEXT: oq3.include "stdgates.inc" id 0 {oq3.trailing_comment = "// the standard gates"}
// COMMENTS-NEXT: oq3.comment "// Standalone"{{$}}
// COMMENTS-NEXT: oq3.qubit_decl "q" {oq3.trailing_comment = "/* one */ // and two"}
// Comments inside a statement, or between its annotation and the rest, go before it.
// COMMENTS-NEXT: oq3.comment "// between annotation and statement"
// COMMENTS-NEXT: oq3.comment "/* inside */"
// COMMENTS-NEXT: oq3.gate_call @x [%{{.*}} : !qcc.qubit_ref] {oq3.annotations = [#oq3.annotation<"ns.name", "args">]}
// COMMENTS-NEXT: oq3.comment "// at the end"
// COMMENTS-NEXT: return

// LEGACY: warning: 'qreg' is deprecated; declare 'q' with 'qubit[n] q;' instead
// LEGACY: warning: 'creg' is deprecated; declare 'c' with 'bit c;' instead

// LEGACY-IR: oq3.qubit_decl "q" [%{{.*}} : !oq3.int] legacy : !oq3.qreg<2>
// LEGACY-IR: oq3.declare "c" legacy : !qcc.ref<!oq3.bit>

//--- program.qasm
OPENQASM 3.1;
include "stdgates.inc";
qubit[2] q;
bit c;
h q;
cx q[0], $1;
rz(pi) q;
measure q[0] -> c;
measure q;
reset q;
barrier;
//--- expressions.qasm
include "stdgates.inc";
qubit q;
// Integer literals keep their base, floats their text.
rx(0x1F) q;
rx(1_000.5e-3) q;
// `-` binds tighter than `*`, and integers are converted to float where needed.
rx(-2 * pi) q;
bit[4] b = "0101";
bit c = 1;
//--- comments.qasm
/* before the
   version line */
OPENQASM 3.1;
include "stdgates.inc";  // the standard gates
// Standalone
qubit q;  /* one */  // and two
@ns.name args
// between annotation and statement
x /* inside */ q;
// at the end
//--- legacy.qasm
qreg q[2];
creg c;
