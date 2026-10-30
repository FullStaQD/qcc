// RUN: qcc-opt %s --convert-qcirc-to-qref --convert-qref-to-qcirc | FileCheck %s

// qcirc -> qref -> qcirc gives back the program, up to the bindings of a `qcf.if`: afterwards they are the qubits that
// its regions act on, in the order of their indices.

// CHECK-LABEL: func.func @main
func.func @main() -> i1 {
  %q0, %q1, %q2 = qcc.static [0, 1, 2] : !qcc.qubit
  %h = qcirc.single h %q0 : !qcc.qubit
  %p, %bit = qcirc.measure z %h : !qcc.qubit -> i1
  // Bound out of index order, and qubit 2 is bound but not acted on.
  %r1, %r2, %r0, %m = qcf.if %bit (%b = %q1, %c = %q2, %a = %p) -> (!qcc.qubit, !qcc.qubit, !qcc.qubit, i1) {
    %a1, %b1 = qcirc.pair cx %a, %b : !qcc.qubit
    %b2, %m1 = qcirc.measure z %b1 : !qcc.qubit -> i1
    qcf.yield %b2, %c, %a1, %m1 : !qcc.qubit, !qcc.qubit, !qcc.qubit, i1
  } else (%b, %c, %a) {
    %false = arith.constant false
    qcf.yield %b, %c, %a, %false : !qcc.qubit, !qcc.qubit, !qcc.qubit, i1
  }
  %x = qcirc.single x %r0 : !qcc.qubit
  return %m : i1
}
// CHECK:         %[[Q:.*]]:3 = qcc.static [0, 1, 2] : !qcc.qubit
// CHECK-NEXT:    %[[H:.*]] = qcirc.single h %[[Q]]#0 : !qcc.qubit
// CHECK-NEXT:    %[[P:.*]], %[[BIT:.*]] = qcirc.measure z %[[H]] : !qcc.qubit -> i1
// CHECK-NEXT:    %[[IF:.*]]:3 = qcf.if %[[BIT]] (%[[A:.*]] = %[[P]], %[[B:.*]] = %[[Q]]#1) -> (!qcc.qubit, !qcc.qubit, i1) {
// CHECK-NEXT:      %[[A1:.*]], %[[B1:.*]] = qcirc.pair cx %[[A]], %[[B]] : !qcc.qubit
// CHECK-NEXT:      %[[B2:.*]], %[[M1:.*]] = qcirc.measure z %[[B1]] : !qcc.qubit -> i1
// CHECK-NEXT:      qcf.yield %[[A1]], %[[B2]], %[[M1]] : !qcc.qubit, !qcc.qubit, i1
// CHECK-NEXT:    } else (%[[X:.*]], %[[Y:.*]]) {
// CHECK-NEXT:      %[[FALSE:.*]] = arith.constant false
// CHECK-NEXT:      qcf.yield %[[X]], %[[Y]], %[[FALSE]] : !qcc.qubit, !qcc.qubit, i1
// CHECK-NEXT:    }
// CHECK-NEXT:    %{{.*}} = qcirc.single x %[[IF]]#0 : !qcc.qubit
// CHECK-NEXT:    return %[[IF]]#2 : i1

// A `qcf.if` without bindings comes back as `scf.if`.
// CHECK-LABEL: func.func @without_bindings
// CHECK-SAME:  (%[[COND:.*]]: i1, %[[VALUE:.*]]: i32) -> i32
func.func @without_bindings(%cond: i1, %value: i32) -> i32 {
  %r = qcf.if %cond -> i32 {
    qcf.yield %value : i32
  } else {
    %zero = arith.constant 0 : i32
    qcf.yield %zero : i32
  }
  return %r : i32
}
// CHECK-NEXT:    %[[R:.*]] = scf.if %[[COND]] -> (i32) {
// CHECK-NEXT:      scf.yield %[[VALUE]] : i32
// CHECK-NEXT:    } else {
// CHECK-NEXT:      %[[ZERO:.*]] = arith.constant 0 : i32
// CHECK-NEXT:      scf.yield %[[ZERO]] : i32
// CHECK-NEXT:    }
// CHECK-NEXT:    return %[[R]] : i32
