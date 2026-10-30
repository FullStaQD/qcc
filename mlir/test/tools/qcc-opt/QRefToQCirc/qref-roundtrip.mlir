// RUN: qcc-opt %s --convert-qref-to-qcirc --convert-qcirc-to-qref | FileCheck %s

// qref -> qcirc -> qref gives back the program, up to the references: afterwards a single `qcc.static_ref` at the top
// names all qubits of the function.

// The example of `qref` from its plan, without the loop.
// CHECK-LABEL: func.func @main
func.func @main() -> i1 attributes {qcc.entry_point} {
  %q0, %q1 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  %theta = arith.constant 0.5 : f64

  qref.single h %q0 : !qcc.qubit_ref
  qref.single rz(%theta) %q1 : f64, !qcc.qubit_ref
  qref.single u_zxz(%theta, %theta, %theta) %q1 : f64, !qcc.qubit_ref
  qref.pair cx %q0, %q1 : !qcc.qubit_ref
  qref.pair rzz(%theta) %q0, %q1 : f64, !qcc.qubit_ref

  %bit = qref.measure z %q0 : !qcc.qubit_ref -> i1
  scf.if %bit {
    qref.single x %q1 : !qcc.qubit_ref
  }

  qref.reset z %q0 : !qcc.qubit_ref
  %m = qref.measure z %q1 : !qcc.qubit_ref -> i1
  return %m : i1
}
// CHECK:         %[[Q:.*]]:2 = qcc.static_ref [0, 1] : !qcc.qubit_ref
// CHECK-NEXT:    %[[THETA:.*]] = arith.constant 5.000000e-01 : f64
// CHECK-NEXT:    qref.single h %[[Q]]#0 : !qcc.qubit_ref
// CHECK-NEXT:    qref.single rz(%[[THETA]]) %[[Q]]#1 : f64, !qcc.qubit_ref
// CHECK-NEXT:    qref.single u_zxz(%[[THETA]], %[[THETA]], %[[THETA]]) %[[Q]]#1 : f64, !qcc.qubit_ref
// CHECK-NEXT:    qref.pair cx %[[Q]]#0, %[[Q]]#1 : !qcc.qubit_ref
// CHECK-NEXT:    qref.pair rzz(%[[THETA]]) %[[Q]]#0, %[[Q]]#1 : f64, !qcc.qubit_ref
// CHECK-NEXT:    %[[BIT:.*]] = qref.measure z %[[Q]]#0 : !qcc.qubit_ref -> i1
// CHECK-NEXT:    scf.if %[[BIT]] {
// CHECK-NEXT:      qref.single x %[[Q]]#1 : !qcc.qubit_ref
// CHECK-NEXT:    }
// CHECK-NEXT:    qref.reset z %[[Q]]#0 : !qcc.qubit_ref
// CHECK-NEXT:    %[[M:.*]] = qref.measure z %[[Q]]#1 : !qcc.qubit_ref -> i1
// CHECK-NEXT:    return %[[M]] : i1

// CHECK-LABEL: func.func @if_else
// CHECK-SAME:  (%[[COND:.*]]: i1) -> i1
func.func @if_else(%cond: i1) -> i1 {
  %q0 = qcc.static_ref [0] : !qcc.qubit_ref
  %bit = scf.if %cond -> i1 {
    %q1 = qcc.static_ref [1] : !qcc.qubit_ref
    qref.pair cx %q0, %q1 : !qcc.qubit_ref
    %m = qref.measure z %q1 : !qcc.qubit_ref -> i1
    scf.yield %m : i1
  } else {
    %false = arith.constant false
    scf.yield %false : i1
  }
  return %bit : i1
}
// CHECK:         %[[Q:.*]]:2 = qcc.static_ref [0, 1] : !qcc.qubit_ref
// CHECK-NEXT:    %[[IF:.*]] = scf.if %[[COND]] -> (i1) {
// CHECK-NEXT:      qref.pair cx %[[Q]]#0, %[[Q]]#1 : !qcc.qubit_ref
// CHECK-NEXT:      %[[M:.*]] = qref.measure z %[[Q]]#1 : !qcc.qubit_ref -> i1
// CHECK-NEXT:      scf.yield %[[M]] : i1
// CHECK-NEXT:    } else {
// CHECK-NEXT:      %[[FALSE:.*]] = arith.constant false
// CHECK-NEXT:      scf.yield %[[FALSE]] : i1
// CHECK-NEXT:    }
// CHECK-NEXT:    return %[[IF]] : i1
