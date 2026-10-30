// RUN: qcc-opt %s --convert-qcirc-to-qref --split-input-file | FileCheck %s

// Every value of a qubit becomes the reference to it.
// CHECK-LABEL: func.func @gates
// CHECK-SAME:  (%[[THETA:.*]]: f64) -> (i1, i1)
func.func @gates(%theta: f64) -> (i1, i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %a1 = qcirc.single h %q0 : !qcc.qubit
  %b1 = qcirc.single rz(%theta) %q1 : f64, !qcc.qubit
  %a2, %b2 = qcirc.pair cx %a1, %b1 : !qcc.qubit
  %a3, %bit0 = qcirc.measure z %a2 : !qcc.qubit -> i1
  %a4 = qcirc.reset x %a3 : !qcc.qubit
  %b3, %bit1 = qcirc.measure x %b2 : !qcc.qubit -> i1
  return %bit0, %bit1 : i1, i1
}
// CHECK:         %[[Q:.*]]:2 = qcc.static_ref [0, 1] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single h %[[Q]]#0 : !qcc.qubit_ref
// CHECK-NEXT:    qref.single rz(%[[THETA]]) %[[Q]]#1 : f64, !qcc.qubit_ref
// CHECK-NEXT:    qref.pair cx %[[Q]]#0, %[[Q]]#1 : !qcc.qubit_ref
// CHECK-NEXT:    %[[BIT0:.*]] = qref.measure z %[[Q]]#0 : !qcc.qubit_ref -> i1
// CHECK-NEXT:    qref.reset x %[[Q]]#0 : !qcc.qubit_ref
// CHECK-NEXT:    %[[BIT1:.*]] = qref.measure x %[[Q]]#1 : !qcc.qubit_ref -> i1
// CHECK-NEXT:    return %[[BIT0]], %[[BIT1]] : i1, i1

// -----

// A result is the same qubit as the operand in its lane, even after a swap.
// CHECK-LABEL: func.func @swap
func.func @swap() {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %a, %b = qcirc.pair swap %q0, %q1 : !qcc.qubit
  %b1 = qcirc.single x %b : !qcc.qubit
  return
}
// CHECK:         %[[Q:.*]]:2 = qcc.static_ref [0, 1] : !qcc.qubit_ref
// CHECK-NEXT:    qref.pair swap %[[Q]]#0, %[[Q]]#1 : !qcc.qubit_ref
// CHECK-NEXT:    qref.single x %[[Q]]#1 : !qcc.qubit_ref
// CHECK-NEXT:    return

// -----

// The bindings and the qubit results of a `qcf.if` are the bound references; the classical results remain.
// CHECK-LABEL: func.func @if_else
// CHECK-SAME:  (%[[COND:.*]]: i1) -> i1
func.func @if_else(%cond: i1) -> i1 {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %a_out, %b_out, %m = qcf.if %cond (%a = %q0, %b = %q1) -> (!qcc.qubit, !qcc.qubit, i1) {
    %a1, %b1 = qcirc.pair cx %a, %b : !qcc.qubit
    %b2, %m1 = qcirc.measure z %b1 : !qcc.qubit -> i1
    qcf.yield %a1, %b2, %m1 : !qcc.qubit, !qcc.qubit, i1
  } else (%x, %y) {
    %false = arith.constant false
    qcf.yield %x, %y, %false : !qcc.qubit, !qcc.qubit, i1
  }
  %b3 = qcirc.single h %b_out : !qcc.qubit
  return %m : i1
}
// CHECK:         %[[Q:.*]]:2 = qcc.static_ref [0, 1] : !qcc.qubit_ref
// CHECK-NEXT:    %[[IF:.*]] = scf.if %[[COND]] -> (i1) {
// CHECK-NEXT:      qref.pair cx %[[Q]]#0, %[[Q]]#1 : !qcc.qubit_ref
// CHECK-NEXT:      %[[M1:.*]] = qref.measure z %[[Q]]#1 : !qcc.qubit_ref -> i1
// CHECK-NEXT:      scf.yield %[[M1]] : i1
// CHECK-NEXT:    } else {
// CHECK-NEXT:      %[[FALSE:.*]] = arith.constant false
// CHECK-NEXT:      scf.yield %[[FALSE]] : i1
// CHECK-NEXT:    }
// CHECK-NEXT:    qref.single h %[[Q]]#1 : !qcc.qubit_ref
// CHECK-NEXT:    return %[[IF]] : i1

// -----

// CHECK-LABEL: func.func @if_without_else
// CHECK-SAME:  (%[[COND:.*]]: i1)
func.func @if_without_else(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  %q_out = qcf.if %cond (%a = %q) -> !qcc.qubit {
    %x = qcirc.single x %a : !qcc.qubit
    qcf.yield %x : !qcc.qubit
  }
  return
}
// CHECK:         %[[Q:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:    scf.if %[[COND]] {
// CHECK-NEXT:      qref.single x %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:    }
// CHECK-NEXT:    return

// -----

// CHECK-LABEL: func.func @nested_if
// CHECK-SAME:  (%[[C0:.*]]: i1, %[[C1:.*]]: i1)
func.func @nested_if(%c0: i1, %c1: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %r0, %r1 = qcf.if %c0 (%a = %q0, %b = %q1) -> (!qcc.qubit, !qcc.qubit) {
    %h = qcirc.single h %a : !qcc.qubit
    %inner = qcf.if %c1 (%c = %b) -> !qcc.qubit {
      %x = qcirc.single x %c : !qcc.qubit
      qcf.yield %x : !qcc.qubit
    }
    qcf.yield %h, %inner : !qcc.qubit, !qcc.qubit
  }
  return
}
// CHECK:         %[[Q:.*]]:2 = qcc.static_ref [0, 1] : !qcc.qubit_ref
// CHECK-NEXT:    scf.if %[[C0]] {
// CHECK-NEXT:      qref.single h %[[Q]]#0 : !qcc.qubit_ref
// CHECK-NEXT:      scf.if %[[C1]] {
// CHECK-NEXT:        qref.single x %[[Q]]#1 : !qcc.qubit_ref
// CHECK-NEXT:      }
// CHECK-NEXT:    }
// CHECK-NEXT:    return
