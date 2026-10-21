// RUN: qcc-opt %s --split-input-file | FileCheck %s
// RUN: qcc-opt %s --split-input-file --mlir-print-op-generic | qcc-opt --split-input-file | FileCheck %s
// RUN: qcc-opt %s --split-input-file --canonicalize | FileCheck %s --check-prefix=CANON

// Round trip of the oq3 dialect. Operations that carry source text survive canonicalization, so nothing that the
// export prints is lost.

// CHECK-LABEL: module attributes {oq3.version = #oq3.version<3, 1>}
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // CHECK: oq3.comment "/* header */" header
    oq3.comment "/* header */" header
    // CHECK: oq3.pragma "ns.name text" hash_prefix
    oq3.pragma "ns.name text" hash_prefix
    // CHECK: oq3.include "stdgates.inc" id 0 {oq3.trailing_comment = "// gates"}
    oq3.include "stdgates.inc" id 0 {oq3.trailing_comment = "// gates"}
    // CHECK: oq3.include "other.inc" id 1 hash "abc"
    oq3.include "other.inc" id 1 hash "abc"
    // CHECK: oq3.comment "// from other.inc" {oq3.from_include = 1 : i64}
    oq3.comment "// from other.inc" {oq3.from_include = 1 : i64}

    // CHECK: %[[TWO:.*]] = oq3.constant #oq3.int<2> : !oq3.int
    %two = oq3.constant #oq3.int<2> : !oq3.int
    // CHECK: %[[Q:.*]] = oq3.qubit_decl "q" [%[[TWO]] : !oq3.int] : !oq3.qreg<2>
    %q = oq3.qubit_decl "q" [%two : !oq3.int] : !oq3.qreg<2>
    // CHECK: %[[R:.*]] = oq3.qubit_decl "r" legacy : !qcc.qubit_ref
    %r = oq3.qubit_decl "r" legacy : !qcc.qubit_ref
    // CHECK: %[[P:.*]] = oq3.physical_qubit 3 : !qcc.qubit_ref
    %p = oq3.physical_qubit 3 : !qcc.qubit_ref

    // CHECK: %[[C:.*]] = oq3.declare "c" [%[[TWO]] : !oq3.int] legacy : !qcc.ref<!oq3.bits<2>>
    %c = oq3.declare "c" [%two : !oq3.int] legacy : !qcc.ref<!oq3.bits<2>>
    // CHECK: %[[BITS:.*]] = oq3.constant #oq3.bitstring<"01"> : !oq3.bits<2>
    %bits = oq3.constant #oq3.bitstring<"01"> : !oq3.bits<2>
    // CHECK: oq3.declare "d" [%[[TWO]] : !oq3.int] = %[[BITS]] : !oq3.bits<2> : !qcc.ref<!oq3.bits<2>>
    %d = oq3.declare "d" [%two : !oq3.int] = %bits : !oq3.bits<2> : !qcc.ref<!oq3.bits<2>>

    // CHECK: %[[HEX:.*]] = oq3.constant #oq3.int<31> : !oq3.int radix hex
    %hex = oq3.constant #oq3.int<31> : !oq3.int radix hex
    // CHECK: %[[F:.*]] = oq3.constant #oq3.float<"1.5e3"> : !oq3.float
    %f = oq3.constant #oq3.float<"1.5e3"> : !oq3.float
    // CHECK: %[[PI:.*]] = oq3.math_constant pi unicode : !oq3.float
    %pi = oq3.math_constant pi unicode : !oq3.float
    // CHECK: %[[NEG:.*]] = oq3.unary neg %[[PI]] : !oq3.float
    %neg = oq3.unary neg %pi : !oq3.float
    // CHECK: %[[HEX_F:.*]] = oq3.cast %[[HEX]] implicit : !oq3.int -> !oq3.float
    %hex_f = oq3.cast %hex implicit : !oq3.int -> !oq3.float
    // CHECK: %[[SUM:.*]] = oq3.binary add %[[HEX_F]], %[[NEG]] : !oq3.float
    %sum = oq3.binary add %hex_f, %neg : !oq3.float
    // CHECK: %[[THETA:.*]] = oq3.cast %[[SUM]] implicit : !oq3.float -> !qcc.angle
    %theta = oq3.cast %sum implicit : !oq3.float -> !qcc.angle
    // CHECK: oq3.binary div %[[THETA]], %[[TWO]] : (!qcc.angle, !oq3.int) -> !qcc.angle
    %half = oq3.binary div %theta, %two : (!qcc.angle, !oq3.int) -> !qcc.angle

    // Negative indices count from the end.
    // CHECK: %[[NEG_TWO:.*]] = oq3.unary neg %[[TWO]] : !oq3.int
    %neg_two = oq3.unary neg %two : !oq3.int
    // CHECK: %[[Q1:.*]] = oq3.qubit_index %[[Q]][%[[NEG_TWO]]] : !oq3.qreg<2>, !oq3.int
    %q1 = oq3.qubit_index %q[%neg_two] : !oq3.qreg<2>, !oq3.int
    // CHECK: oq3.gate_call @rx(%[[THETA]] : !qcc.angle) [%[[Q]] : !oq3.qreg<2>] {oq3.annotations = [#oq3.annotation<"ns.a", "">, #oq3.annotation<"ns.b", "x y">]}
    oq3.gate_call @rx(%theta : !qcc.angle) [%q : !oq3.qreg<2>] {oq3.annotations = [#oq3.annotation<"ns.a", "">, #oq3.annotation<"ns.b", "x y">]}
    // CHECK: oq3.gate_call @cx [%[[R]], %[[P]] : !qcc.qubit_ref, !qcc.qubit_ref]
    oq3.gate_call @cx [%r, %p : !qcc.qubit_ref, !qcc.qubit_ref]
    // CHECK: oq3.gate_call @gphase(%[[THETA]] : !qcc.angle){{$}}
    oq3.gate_call @gphase(%theta : !qcc.angle)
    // CHECK: oq3.reset %[[Q]] : !oq3.qreg<2>
    oq3.reset %q : !oq3.qreg<2>
    // CHECK: oq3.barrier [%[[Q]], %[[R]] : !oq3.qreg<2>, !qcc.qubit_ref]
    oq3.barrier [%q, %r : !oq3.qreg<2>, !qcc.qubit_ref]
    // CHECK: oq3.barrier{{$}}
    oq3.barrier

    // CHECK: %[[M:.*]] = oq3.measure %[[Q]] : !oq3.qreg<2> -> !oq3.bits<2>
    %m = oq3.measure %q : !oq3.qreg<2> -> !oq3.bits<2>
    // CHECK: qcc.ref.store %[[M]], %[[C]] {oq3.arrow} : !qcc.ref<!oq3.bits<2>>
    qcc.ref.store %m, %c {oq3.arrow} : !qcc.ref<!oq3.bits<2>>
    // CHECK: %[[C0:.*]] = oq3.subref %[[C]][%[[NEG_TWO]]] : !qcc.ref<!oq3.bits<2>>, !oq3.int -> !qcc.ref<!oq3.bit>
    %c0 = oq3.subref %c[%neg_two] : !qcc.ref<!oq3.bits<2>>, !oq3.int -> !qcc.ref<!oq3.bit>
    // CHECK: %[[M1:.*]] = oq3.measure %[[Q1]] : !qcc.qubit_ref -> !oq3.bit
    %m1 = oq3.measure %q1 : !qcc.qubit_ref -> !oq3.bit
    // CHECK: qcc.ref.store %[[M1]], %[[C0]] : !qcc.ref<!oq3.bit>
    qcc.ref.store %m1, %c0 : !qcc.ref<!oq3.bit>
    // CHECK: qcc.ref.load %[[D:.*]] : !qcc.ref<!oq3.bits<2>>
    %loaded = qcc.ref.load %d : !qcc.ref<!oq3.bits<2>>
    qcc.ref.store %loaded, %c : !qcc.ref<!oq3.bits<2>>
    // CHECK: oq3.comment "// end"{{$}}
    oq3.comment "// end"
    return
  }
}

// Statements survive, and so do the expressions they use. Unused expressions may go.
// CANON-LABEL: module attributes {oq3.version = #oq3.version<3, 1>}
// CANON:       oq3.comment "/* header */" header
// CANON-NEXT:  oq3.pragma
// CANON-NEXT:  oq3.include "stdgates.inc"
// CANON-NEXT:  oq3.include "other.inc"
// CANON-NEXT:  oq3.comment "// from other.inc"
// CANON:       oq3.qubit_decl "q"
// CANON:       oq3.qubit_decl "r"
// CANON:       oq3.declare "c"
// CANON:       oq3.declare "d"
// CANON-NOT:   oq3.binary div
// CANON:       oq3.gate_call @rx
// CANON:       oq3.comment "// end"

// -----

// A global definition is any symbol of the module but the entry function, with its marker in the entry body.
// CHECK-LABEL: module attributes {oq3.version = #oq3.version<3, implicit>}
module attributes {oq3.version = #oq3.version<3, implicit>} {
  func.func private @f()
  func.func @main() attributes {qcc.entry_point} {
    // CHECK: oq3.defined @f
    oq3.defined @f
    func.call @f() : () -> ()
    return
  }
}
