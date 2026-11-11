// RUN: qcc-opt %s --split-input-file --convert-qref-to-oq3 | FileCheck %s

// A value that is used twice is converted once.

// CHECK-LABEL: func.func @shared_expression
func.func @shared_expression() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  %a = arith.constant 0.5 : f64
  %b = arith.constant 0.25 : f64
  %sum = arith.addf %a, %b : f64
  qref.single rx(%sum) %q : f64, !qcc.qubit_ref
  qref.single ry(%sum) %q : f64, !qcc.qubit_ref
  return
}
// CHECK:         %[[SUM:.*]] = oq3.binary add %{{.*}}, %{{.*}} : !oq3.float
// CHECK-NEXT:    %[[RX:.*]] = oq3.cast %[[SUM]] implicit : !oq3.float -> !qcc.angle
// CHECK-NEXT:    oq3.gate_call @rx(%[[RX]] : !qcc.angle)
// CHECK-NEXT:    %[[RY:.*]] = oq3.cast %[[SUM]] implicit : !oq3.float -> !qcc.angle
// CHECK-NEXT:    oq3.gate_call @ry(%[[RY]] : !qcc.angle)
// CHECK-NEXT:    return

// -----

// Integer-to-float conversions, gate parameters, and bit constants are implicit casts.

// CHECK-LABEL: func.func @implicit_casts
func.func @implicit_casts() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  %b = memref.alloca() : memref<i1>
  %c2 = arith.constant 2 : i64
  %f = arith.sitofp %c2 : i64 to f64
  qref.single rx(%f) %q : f64, !qcc.qubit_ref
  %true = arith.constant true
  memref.store %true, %b[] : memref<i1>
  return
}
// CHECK:         %[[B:.*]] = oq3.declare "c1" : !qcc.ref<!oq3.bit>
// CHECK-NEXT:    %[[TWO:.*]] = oq3.constant #oq3.int<2> : !oq3.int
// CHECK-NEXT:    %[[F:.*]] = oq3.cast %[[TWO]] implicit : !oq3.int -> !oq3.float
// CHECK-NEXT:    %[[A:.*]] = oq3.cast %[[F]] implicit : !oq3.float -> !qcc.angle
// CHECK-NEXT:    oq3.gate_call @rx(%[[A]] : !qcc.angle)
// CHECK-NEXT:    %[[ONE:.*]] = oq3.constant #oq3.int<1> : !oq3.int
// CHECK-NEXT:    %[[TRUE:.*]] = oq3.cast %[[ONE]] implicit : !oq3.int -> !oq3.bit
// CHECK-NEXT:    qcc.ref.store %[[TRUE]], %[[B]] : !qcc.ref<!oq3.bit>

// -----

// Integer extensions and index casts disappear: every integer is an `int`.

// CHECK-LABEL: func.func @forwarded_casts
func.func @forwarded_casts() attributes {qcc.entry_point} {
  %r = qcc.alloc : tensor<2x!qcc.qubit_ref>
  %c1 = arith.constant 1 : i32
  %wide = arith.extsi %c1 : i32 to i64
  %index = arith.index_cast %wide : i64 to index
  %q = tensor.extract %r[%index] : tensor<2x!qcc.qubit_ref>
  qref.single x %q : !qcc.qubit_ref
  return
}
// CHECK:         %[[R:.*]] = oq3.qubit_decl "q0"
// CHECK-NEXT:    %[[ONE:.*]] = oq3.constant #oq3.int<1> : !oq3.int
// CHECK-NEXT:    %[[Q:.*]] = oq3.qubit_index %[[R]][%[[ONE]]] : !oq3.qreg<2>, !oq3.int
// CHECK-NEXT:    oq3.gate_call @x [%[[Q]] : !qcc.qubit_ref]

// -----

// A measurement in a `bit` variable of its own is read again right before each use.

// CHECK-LABEL: func.func @bit_reads
func.func @bit_reads() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  %b = memref.alloca() : memref<i1>
  %c = memref.alloca() : memref<i1>
  %m = qref.measure z %q : !qcc.qubit_ref -> i1
  qref.single x %q : !qcc.qubit_ref
  memref.store %m, %b[] : memref<i1>
  memref.store %m, %c[] : memref<i1>
  return
}
// CHECK:         %[[B:.*]] = oq3.declare "c1" : !qcc.ref<!oq3.bit>
// CHECK-NEXT:    %[[C:.*]] = oq3.declare "c2" : !qcc.ref<!oq3.bit>
// CHECK-NEXT:    %[[M:.*]] = oq3.measure %{{.*}} : !qcc.qubit_ref -> !oq3.bit
// CHECK-NEXT:    %[[VAR:.*]] = oq3.declare "m3" = %[[M]] : !oq3.bit : !qcc.ref<!oq3.bit>
// CHECK-NEXT:    oq3.gate_call @x
// CHECK-NEXT:    %[[M1:.*]] = qcc.ref.load %[[VAR]] : !qcc.ref<!oq3.bit>
// CHECK-NEXT:    qcc.ref.store %[[M1]], %[[B]] : !qcc.ref<!oq3.bit>
// CHECK-NEXT:    %[[M2:.*]] = qcc.ref.load %[[VAR]] : !qcc.ref<!oq3.bit>
// CHECK-NEXT:    qcc.ref.store %[[M2]], %[[C]] : !qcc.ref<!oq3.bit>

// -----

// Literals are non-negative; negative constants, -0.0 among them, are negated literals.

// CHECK-LABEL: func.func @negative_constants
func.func @negative_constants() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  %zero = arith.constant -0.0 : f64
  %c = arith.constant -3 : i64
  %f = arith.sitofp %c : i64 to f64
  %sum = arith.addf %zero, %f : f64
  qref.single rx(%sum) %q : f64, !qcc.qubit_ref
  return
}
// CHECK:         %[[ZERO:.*]] = oq3.constant #oq3.float<"0.0"> : !oq3.float
// CHECK-NEXT:    %[[NEG_ZERO:.*]] = oq3.unary neg %[[ZERO]] : !oq3.float
// CHECK-NEXT:    %[[THREE:.*]] = oq3.constant #oq3.int<3> : !oq3.int
// CHECK-NEXT:    %[[NEG_THREE:.*]] = oq3.unary neg %[[THREE]] : !oq3.int
// CHECK-NEXT:    %[[F:.*]] = oq3.cast %[[NEG_THREE]] implicit : !oq3.int -> !oq3.float
// CHECK-NEXT:    oq3.binary add %[[NEG_ZERO]], %[[F]] : !oq3.float

// -----

// The module keeps the target's data layout. An existing OpenQASM version is not replaced.
// The `f32` widened to an `f64` gate parameter is the target's `float`, cast to an angle implicitly.

// CHECK-LABEL: module attributes {dlti.dl_spec = #dlti.dl_spec<index = 32 : i64>, oq3.version = #oq3.version<3, 0>}
module attributes {oq3.version = #oq3.version<3, 0>, dlti.dl_spec = #dlti.dl_spec<index = 32>} {
  func.func @kept_module_attributes() attributes {qcc.entry_point} {
    %q = qcc.alloc : !qcc.qubit_ref
    %a = arith.constant 0.1 : f32
    %theta = arith.extf %a : f32 to f64
    qref.single rx(%theta) %q : f64, !qcc.qubit_ref
    return
  }
}
// CHECK:         %[[A:.*]] = oq3.constant #oq3.float<"0.1"> : !oq3.float
// CHECK-NEXT:    %[[THETA:.*]] = oq3.cast %[[A]] implicit : !oq3.float -> !qcc.angle
// CHECK-NEXT:    oq3.gate_call @rx(%[[THETA]] : !qcc.angle)
