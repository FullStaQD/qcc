// RUN: qcc-translate --split-input-file --import-openqasm %s | FileCheck %s

// The IR that the importer builds.

// CHECK-LABEL: module attributes {oq3.version = #oq3.version<3, 1>} {
// CHECK-NEXT:    func.func @main() attributes {qcc.entry_point} {
// CHECK-NEXT:      oq3.include "stdgates.inc" id 0
// CHECK-NEXT:      %[[TWO:.*]] = oq3.constant #oq3.int<2> : !oq3.int
// CHECK-NEXT:      %[[Q:.*]] = oq3.qubit_decl "q" [%[[TWO]] : !oq3.int] : !oq3.qreg<2>
// CHECK-NEXT:      %[[C:.*]] = oq3.declare "c" : !qcc.ref<!oq3.bit>
// CHECK-NEXT:      oq3.gate_call @h [%[[Q]] : !oq3.qreg<2>]
// CHECK-NEXT:      %[[ZERO:.*]] = oq3.constant #oq3.int<0> : !oq3.int
// CHECK-NEXT:      %[[Q0:.*]] = oq3.qubit_index %[[Q]][%[[ZERO]]] : !oq3.qreg<2>, !oq3.int
// CHECK-NEXT:      %[[P1:.*]] = oq3.physical_qubit 1 : !qcc.qubit_ref
// CHECK-NEXT:      oq3.gate_call @cx [%[[Q0]], %[[P1]] : !qcc.qubit_ref, !qcc.qubit_ref]
// CHECK-NEXT:      %[[PI:.*]] = oq3.math_constant pi : !oq3.float
// CHECK-NEXT:      %[[ANGLE:.*]] = oq3.cast %[[PI]] implicit : !oq3.float -> !qcc.angle
// CHECK-NEXT:      oq3.gate_call @rz(%[[ANGLE]] : !qcc.angle) [%[[Q]] : !oq3.qreg<2>]
// Every use of `q[0]` indexes anew, as the source does.
// CHECK-NEXT:      %[[ZERO_AGAIN:.*]] = oq3.constant #oq3.int<0> : !oq3.int
// CHECK-NEXT:      %[[Q0_AGAIN:.*]] = oq3.qubit_index %[[Q]][%[[ZERO_AGAIN]]] : !oq3.qreg<2>, !oq3.int
// CHECK-NEXT:      %[[M:.*]] = oq3.measure %[[Q0_AGAIN]] : !qcc.qubit_ref -> !oq3.bit
// CHECK-NEXT:      qcc.ref.store %[[M]], %[[C]] : !qcc.ref<!oq3.bit>
// CHECK-NEXT:      oq3.measure %[[Q]] : !oq3.qreg<2> -> !oq3.bits<2>
// CHECK-NEXT:      oq3.reset %[[Q]] : !oq3.qreg<2>
// CHECK-NEXT:      oq3.barrier{{$}}
// CHECK-NEXT:      return
// CHECK-NEXT:    }
// CHECK-NEXT:  }

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

// -----

// A program without a version line gets the default version.
// CHECK-LABEL: module attributes {oq3.version = #oq3.version<3, 1>}

// Integer literals are stored by value, floats by their text.
// CHECK:      %[[HEX:.*]] = oq3.constant #oq3.int<31> : !oq3.int
// CHECK-NEXT: %[[HEX_F:.*]] = oq3.cast %[[HEX]] implicit : !oq3.int -> !oq3.float
// CHECK-NEXT: %[[HEX_A:.*]] = oq3.cast %[[HEX_F]] implicit : !oq3.float -> !qcc.angle
// CHECK-NEXT: oq3.gate_call @rx(%[[HEX_A]] : !qcc.angle)

// CHECK:      oq3.constant #oq3.float<"1000.5e-3"> : !oq3.float

// `-` binds tighter than `*`, and integers are converted to float where needed.
// CHECK:      %[[TWO:.*]] = oq3.constant #oq3.int<2> : !oq3.int
// CHECK-NEXT: %[[NEG:.*]] = oq3.unary neg %[[TWO]] : !oq3.int
// CHECK-NEXT: %[[PI:.*]] = oq3.math_constant pi : !oq3.float
// CHECK-NEXT: %[[NEG_F:.*]] = oq3.cast %[[NEG]] implicit : !oq3.int -> !oq3.float
// CHECK-NEXT: %[[PROD:.*]] = oq3.binary mul %[[NEG_F]], %[[PI]] : !oq3.float
// CHECK-NEXT: oq3.cast %[[PROD]] implicit : !oq3.float -> !qcc.angle

// CHECK:      %[[BITS:.*]] = oq3.constant #oq3.bitstring<"0101"> : !oq3.bits<4>
// CHECK-NEXT: %[[B:.*]] = oq3.declare "b" [%{{.*}} : !oq3.int] = %[[BITS]] : !oq3.bits<4> : !qcc.ref<!oq3.bits<4>>
// CHECK-NEXT: %[[ONE:.*]] = oq3.constant #oq3.int<1> : !oq3.int
// CHECK-NEXT: %[[ONE_BIT:.*]] = oq3.cast %[[ONE]] implicit : !oq3.int -> !oq3.bit
// CHECK-NEXT: oq3.declare "c" = %[[ONE_BIT]] : !oq3.bit : !qcc.ref<!oq3.bit>

include "stdgates.inc";
qubit q;
rx(0x1F) q;
rx(1_000.5e-3) q;
rx(-2 * pi) q;
bit[4] b = "0101";
bit c = 1;

// -----

// `OPENQASM 3;` is 3.0. Comments are dropped, and annotations attach to the following statement.
// CHECK-LABEL: module attributes {oq3.version = #oq3.version<3, 0>}
// CHECK:       oq3.include "stdgates.inc" id 0
// CHECK-NEXT:  oq3.qubit_decl "q"
// CHECK-NEXT:  oq3.gate_call @x [%{{.*}} : !qcc.qubit_ref] {oq3.annotations = [#oq3.annotation<"ns.name", "args">]}
// CHECK-NEXT:  return

/* before the
   version line */
OPENQASM 3;
include "stdgates.inc";  // the standard gates
qubit q;  /* one */  // and two
@ns.name args
// between annotation and statement
x /* inside */ q;
