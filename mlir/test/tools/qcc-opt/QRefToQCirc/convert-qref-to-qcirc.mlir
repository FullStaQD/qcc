// RUN: qcc-opt %s --convert-qref-to-qcirc --split-input-file | FileCheck %s

// Each op consumes the current value of its qubits and returns the next one.
// CHECK-LABEL: func.func @gates
// CHECK-SAME:  (%[[THETA:.*]]: f64) -> (i1, i1)
func.func @gates(%theta: f64) -> (i1, i1) {
  %q0, %q1 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  qref.single h %q0 : !qcc.qubit_ref
  qref.single rz(%theta) %q1 : f64, !qcc.qubit_ref
  qref.pair cx %q0, %q1 : !qcc.qubit_ref
  %b0 = qref.measure z %q0 : !qcc.qubit_ref -> i1
  qref.reset x %q0 : !qcc.qubit_ref
  %b1 = qref.measure x %q1 : !qcc.qubit_ref -> i1
  return %b0, %b1 : i1, i1
}
// CHECK:         %[[Q:.*]]:2 = qcc.static [0, 1] : !qcc.qubit
// CHECK-NEXT:    %[[A1:.*]] = qcirc.single h %[[Q]]#0 : !qcc.qubit
// CHECK-NEXT:    %[[B1:.*]] = qcirc.single rz(%[[THETA]]) %[[Q]]#1 : f64, !qcc.qubit
// CHECK-NEXT:    %[[A2:.*]], %[[B2:.*]] = qcirc.pair cx %[[A1]], %[[B1]] : !qcc.qubit
// CHECK-NEXT:    %[[A3:.*]], %[[BIT0:.*]] = qcirc.measure z %[[A2]] : !qcc.qubit -> i1
// CHECK-NEXT:    %{{.*}} = qcirc.reset x %[[A3]] : !qcc.qubit
// CHECK-NEXT:    %{{.*}}, %[[BIT1:.*]] = qcirc.measure x %[[B2]] : !qcc.qubit -> i1
// CHECK-NEXT:    return %[[BIT0]], %[[BIT1]] : i1, i1

// -----

// References with the same index name the same qubit, wherever they sit. The `qcc.static` creates every qubit that is
// named, whether acted on or not.
// CHECK-LABEL: func.func @static_names
func.func @static_names() {
  %a = qcc.static_ref [3] : !qcc.qubit_ref
  qref.single h %a : !qcc.qubit_ref
  %b, %c = qcc.static_ref [0, 3] : !qcc.qubit_ref
  qref.pair cx %c, %b : !qcc.qubit_ref
  %unused = qcc.static_ref [5] : !qcc.qubit_ref
  return
}
// CHECK:         %[[Q:.*]]:3 = qcc.static [0, 3, 5] : !qcc.qubit
// CHECK-NEXT:    %[[H:.*]] = qcirc.single h %[[Q]]#1 : !qcc.qubit
// CHECK-NEXT:    %{{.*}}, %{{.*}} = qcirc.pair cx %[[H]], %[[Q]]#0 : !qcc.qubit
// CHECK-NEXT:    return

// -----

// Without an else region, the `qcf.if` omits it too: it passes the bound qubits on.
// CHECK-LABEL: func.func @if_without_else
// CHECK-SAME:  (%[[COND:.*]]: i1)
func.func @if_without_else(%cond: i1) {
  %q0, %q1 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  scf.if %cond {
    qref.single x %q1 : !qcc.qubit_ref
  }
  qref.pair cx %q0, %q1 : !qcc.qubit_ref
  return
}
// CHECK:         %[[Q:.*]]:2 = qcc.static [0, 1] : !qcc.qubit
// CHECK-NEXT:    %[[IF:.*]] = qcf.if %[[COND]] (%[[A:.*]] = %[[Q]]#1) -> !qcc.qubit {
// CHECK-NEXT:      %[[X:.*]] = qcirc.single x %[[A]] : !qcc.qubit
// CHECK-NEXT:      qcf.yield %[[X]] : !qcc.qubit
// CHECK-NEXT:    }
// CHECK-NEXT:    %{{.*}}, %{{.*}} = qcirc.pair cx %[[Q]]#0, %[[IF]] : !qcc.qubit
// CHECK-NEXT:    return

// -----

// The bindings are the qubits that either region acts on, in the order of their indices, wherever they are named.
// Classical results follow the qubits.
// CHECK-LABEL: func.func @if_else
// CHECK-SAME:  (%[[COND:.*]]: i1) -> i1
func.func @if_else(%cond: i1) -> i1 {
  %q2 = qcc.static_ref [2] : !qcc.qubit_ref
  %q0 = qcc.static_ref [0] : !qcc.qubit_ref
  %bit = scf.if %cond -> i1 {
    %m = qref.measure z %q2 : !qcc.qubit_ref -> i1
    scf.yield %m : i1
  } else {
    %q1 = qcc.static_ref [1] : !qcc.qubit_ref
    qref.pair cz %q1, %q0 : !qcc.qubit_ref
    %false = arith.constant false
    scf.yield %false : i1
  }
  return %bit : i1
}
// CHECK:         %[[Q:.*]]:3 = qcc.static [0, 1, 2] : !qcc.qubit
// CHECK-NEXT:    %[[IF:.*]]:4 = qcf.if %[[COND]] (%[[A0:.*]] = %[[Q]]#0, %[[A1:.*]] = %[[Q]]#1, %[[A2:.*]] = %[[Q]]#2) -> (!qcc.qubit, !qcc.qubit, !qcc.qubit, i1) {
// CHECK-NEXT:      %[[M2:.*]], %[[M:.*]] = qcirc.measure z %[[A2]] : !qcc.qubit -> i1
// CHECK-NEXT:      qcf.yield %[[A0]], %[[A1]], %[[M2]], %[[M]] : !qcc.qubit, !qcc.qubit, !qcc.qubit, i1
// CHECK-NEXT:    } else (%[[B0:.*]], %[[B1:.*]], %[[B2:.*]]) {
// CHECK-NEXT:      %[[L:.*]], %[[R:.*]] = qcirc.pair cz %[[B1]], %[[B0]] : !qcc.qubit
// CHECK-NEXT:      %[[FALSE:.*]] = arith.constant false
// CHECK-NEXT:      qcf.yield %[[R]], %[[L]], %[[B2]], %[[FALSE]] : !qcc.qubit, !qcc.qubit, !qcc.qubit, i1
// CHECK-NEXT:    }
// CHECK-NEXT:    return %[[IF]]#3 : i1

// -----

// A nested `scf.if` becomes a nested `qcf.if`, which binds the qubits its own regions act on.
// CHECK-LABEL: func.func @nested_if
// CHECK-SAME:  (%[[C0:.*]]: i1, %[[C1:.*]]: i1)
func.func @nested_if(%c0: i1, %c1: i1) {
  %q0, %q1 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  scf.if %c0 {
    qref.single h %q0 : !qcc.qubit_ref
    scf.if %c1 {
      qref.single x %q1 : !qcc.qubit_ref
    }
  }
  return
}
// CHECK:         %[[Q:.*]]:2 = qcc.static [0, 1] : !qcc.qubit
// CHECK-NEXT:    %{{.*}}:2 = qcf.if %[[C0]] (%[[A0:.*]] = %[[Q]]#0, %[[A1:.*]] = %[[Q]]#1) -> (!qcc.qubit, !qcc.qubit) {
// CHECK-NEXT:      %[[H:.*]] = qcirc.single h %[[A0]] : !qcc.qubit
// CHECK-NEXT:      %[[INNER:.*]] = qcf.if %[[C1]] (%[[B1:.*]] = %[[A1]]) -> !qcc.qubit {
// CHECK-NEXT:        %[[X:.*]] = qcirc.single x %[[B1]] : !qcc.qubit
// CHECK-NEXT:        qcf.yield %[[X]] : !qcc.qubit
// CHECK-NEXT:      }
// CHECK-NEXT:      qcf.yield %[[H]], %[[INNER]] : !qcc.qubit, !qcc.qubit
// CHECK-NEXT:    }
// CHECK-NEXT:    return

// -----

// An `scf.if` without qubit ops stays.
// CHECK-LABEL: func.func @classical_if
// CHECK-SAME:  (%[[COND:.*]]: i1, %[[A:.*]]: i32, %[[B:.*]]: i32) -> i32
func.func @classical_if(%cond: i1, %a: i32, %b: i32) -> i32 {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  %r = scf.if %cond -> i32 {
    scf.yield %a : i32
  } else {
    scf.yield %b : i32
  }
  return %r : i32
}
// CHECK:         %[[Q:.*]] = qcc.static [0] : !qcc.qubit
// CHECK-NEXT:    %{{.*}} = qcirc.single h %[[Q]] : !qcc.qubit
// CHECK-NEXT:    %[[R:.*]] = scf.if %[[COND]] -> (i32) {
// CHECK-NEXT:      scf.yield %[[A]] : i32
// CHECK-NEXT:    } else {
// CHECK-NEXT:      scf.yield %[[B]] : i32
// CHECK-NEXT:    }
// CHECK-NEXT:    return %[[R]] : i32

// -----

// A function without qubit references is left alone, calls included.
// CHECK-LABEL: func.func @no_qubits
// CHECK-SAME:  (%[[A:.*]]: i32) -> i32
func.func @no_qubits(%a: i32) -> i32 {
  %r = func.call @no_qubits(%a) : (i32) -> i32
  return %r : i32
}
// CHECK-NEXT:    %[[R:.*]] = call @no_qubits(%[[A]]) : (i32) -> i32
// CHECK-NEXT:    return %[[R]] : i32
