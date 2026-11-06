// RUN: qcc-opt %s --convert-oq3-to-qref | FileCheck %s

// Arithmetic on angles: every result is reduced to [0, 2π).
// TODO: Revisit, inconsistency in the specification: https://github.com/openqasm/openqasm/issues/703

// CHECK-LABEL: func.func @main
func.func @main() attributes {qcc.entry_point} {
  %q = oq3.qubit_decl "q" : !qcc.qubit_ref
  %pi = oq3.math_constant pi : !oq3.float
  // CHECK:         %[[PI:.*]] = arith.constant 3.1415926535897931 : f64
  // CHECK:         %[[THETA:.*]] = arith.select
  %theta = oq3.cast %pi implicit : !oq3.float -> !qcc.angle

  // Scaling by an integer converts the integer.
  // CHECK-NEXT:    %[[THREE:.*]] = arith.constant 3 : i64
  // CHECK-NEXT:    %[[FACTOR:.*]] = arith.sitofp %[[THREE]] : i64 to f64
  // CHECK-NEXT:    %[[PROD:.*]] = arith.mulf %[[FACTOR]], %[[THETA]] : f64
  // CHECK-NEXT:    %[[TWO_PI:.*]] = arith.constant 6.2831853071795862 : f64
  // CHECK-NEXT:    %[[REM:.*]] = arith.remf %[[PROD]], %[[TWO_PI]] : f64
  // CHECK:         %[[SCALED:.*]] = arith.select
  %c3 = oq3.constant #oq3.int<3> : !oq3.int
  %scaled = oq3.binary mul %c3, %theta : (!oq3.int, !qcc.angle) -> !qcc.angle

  // CHECK-NEXT:    %[[TWO:.*]] = arith.constant 2 : i64
  // CHECK-NEXT:    %[[DIVISOR:.*]] = arith.sitofp %[[TWO]] : i64 to f64
  // CHECK-NEXT:    %[[QUOT:.*]] = arith.divf %[[SCALED]], %[[DIVISOR]] : f64
  // CHECK:         arith.remf %[[QUOT]]
  // CHECK:         %[[HALF:.*]] = arith.select
  %c2 = oq3.constant #oq3.int<2> : !oq3.int
  %half = oq3.binary div %scaled, %c2 : (!qcc.angle, !oq3.int) -> !qcc.angle

  // CHECK-NEXT:    %[[SUM:.*]] = arith.addf %[[HALF]], %[[THETA]] : f64
  // CHECK:         arith.remf %[[SUM]]
  // CHECK:         %[[REDUCED_SUM:.*]] = arith.select
  %sum = oq3.binary add %half, %theta : !qcc.angle

  // CHECK-NEXT:    %[[NEG:.*]] = arith.negf %[[REDUCED_SUM]] : f64
  // CHECK:         arith.remf %[[NEG]]
  // CHECK:         %[[REDUCED_NEG:.*]] = arith.select
  // CHECK-NEXT:    qref.single rz(%[[REDUCED_NEG]]) %{{.*}} : f64, !qcc.qubit_ref
  %neg = oq3.unary neg %sum : !qcc.angle
  oq3.gate_call @rz(%neg : !qcc.angle) [%q : !qcc.qubit_ref]
  return
}
