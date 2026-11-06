// RUN: qcc-opt %s --convert-qcirc-to-qvec --split-input-file | FileCheck %s

// CHECK-LABEL: func.func @gates
// CHECK-SAME:  (%[[THETA:.*]]: f64) -> (i1, i1)
func.func @gates(%theta: f64) -> (i1, i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %a1 = qcirc.single h %q0 : !qcc.qubit
  %b1 = qcirc.single rz(%theta) %q1 : f64, !qcc.qubit
  %a2, %b2 = qcirc.pair cx %a1, %b1 : !qcc.qubit
  %a3, %b3 = qcirc.pair rzz(%theta) %a2, %b2 : f64, !qcc.qubit
  %a4, %bit0 = qcirc.measure z %a3 : !qcc.qubit -> i1
  %a5 = qcirc.reset x %a4 : !qcc.qubit
  %b4, %bit1 = qcirc.measure x %b3 : !qcc.qubit -> i1
  return %bit0, %bit1 : i1, i1
}
// CHECK:         %[[Q:.*]]:2 = qcc.static [0, 1] : !qcc.qubit
// CHECK-DAG:     %[[A0:.*]] = vector.from_elements %[[Q]]#0 : vector<1x!qcc.qubit>
// CHECK-DAG:     %[[B0:.*]] = vector.from_elements %[[Q]]#1 : vector<1x!qcc.qubit>
// CHECK:         %[[A1:.*]] = qvec.single h %[[A0]] : vector<1x!qcc.qubit>
// CHECK-NEXT:    %[[T0:.*]] = vector.from_elements %[[THETA]] : vector<1xf64>
// CHECK-NEXT:    %[[B1:.*]] = qvec.single rz(%[[T0]]) %[[B0]] : vector<1xf64>, vector<1x!qcc.qubit>
// CHECK-NEXT:    %[[A2:.*]], %[[B2:.*]] = qvec.pair cx %[[A1]], %[[B1]] : vector<1x!qcc.qubit>
// CHECK-NEXT:    %[[T1:.*]] = vector.from_elements %[[THETA]] : vector<1xf64>
// CHECK-NEXT:    %[[A3:.*]], %[[B3:.*]] = qvec.pair rzz(%[[T1]]) %[[A2]], %[[B2]] : vector<1xf64>, vector<1x!qcc.qubit>
// CHECK-NEXT:    %[[A4:.*]], %[[BITS0:.*]] = qvec.measure z %[[A3]] : vector<1x!qcc.qubit> -> vector<1xi1>
// CHECK-NEXT:    %[[BIT0:.*]] = vector.extract %[[BITS0]][0] : i1 from vector<1xi1>
// CHECK-NEXT:    qvec.reset x %[[A4]] : vector<1x!qcc.qubit>
// CHECK-NEXT:    %{{.*}}, %[[BITS1:.*]] = qvec.measure x %[[B3]] : vector<1x!qcc.qubit> -> vector<1xi1>
// CHECK-NEXT:    %[[BIT1:.*]] = vector.extract %[[BITS1]][0] : i1 from vector<1xi1>
// CHECK-NEXT:    return %[[BIT0]], %[[BIT1]] : i1, i1

// -----

// The bindings become captures of the bound vectors, in whatever order they are bound; the results stay.
// CHECK-LABEL: func.func @if_else
// CHECK-SAME:  (%[[COND:.*]]: i1) -> i1
func.func @if_else(%cond: i1) -> i1 {
  %q0, %q1, %q2 = qcc.static [0, 1, 2] : !qcc.qubit
  %h = qcirc.single h %q0 : !qcc.qubit
  %b_out, %c_out, %a_out, %m = qcf.if %cond (%b = %q1, %c = %q2, %a = %h) -> (!qcc.qubit, !qcc.qubit, !qcc.qubit, i1) {
    %a1, %b1 = qcirc.pair cx %a, %b : !qcc.qubit
    %b2, %m1 = qcirc.measure z %b1 : !qcc.qubit -> i1
    qcf.yield %b2, %c, %a1, %m1 : !qcc.qubit, !qcc.qubit, !qcc.qubit, i1
  } else (%y, %z, %x) {
    %false = arith.constant false
    qcf.yield %y, %z, %x, %false : !qcc.qubit, !qcc.qubit, !qcc.qubit, i1
  }
  %b3 = qcirc.single h %b_out : !qcc.qubit
  return %m : i1
}
// CHECK:         %[[Q:.*]]:3 = qcc.static [0, 1, 2] : !qcc.qubit
// CHECK-DAG:     %[[A:.*]] = vector.from_elements %[[Q]]#0 : vector<1x!qcc.qubit>
// CHECK-DAG:     %[[B:.*]] = vector.from_elements %[[Q]]#1 : vector<1x!qcc.qubit>
// CHECK-DAG:     %[[C:.*]] = vector.from_elements %[[Q]]#2 : vector<1x!qcc.qubit>
// CHECK:         %[[H:.*]] = qvec.single h %[[A]] : vector<1x!qcc.qubit>
// CHECK-NEXT:    %[[IF:.*]]:4 = scf.if %[[COND]] -> (vector<1x!qcc.qubit>, vector<1x!qcc.qubit>, vector<1x!qcc.qubit>, i1) {
// CHECK-NEXT:      %[[A1:.*]], %[[B1:.*]] = qvec.pair cx %[[H]], %[[B]] : vector<1x!qcc.qubit>
// CHECK-NEXT:      %[[B2:.*]], %[[BITS:.*]] = qvec.measure z %[[B1]] : vector<1x!qcc.qubit> -> vector<1xi1>
// CHECK-NEXT:      %[[M1:.*]] = vector.extract %[[BITS]][0] : i1 from vector<1xi1>
// CHECK-NEXT:      scf.yield %[[B2]], %[[C]], %[[A1]], %[[M1]] : vector<1x!qcc.qubit>, vector<1x!qcc.qubit>, vector<1x!qcc.qubit>, i1
// CHECK-NEXT:    } else {
// CHECK-NEXT:      %[[FALSE:.*]] = arith.constant false
// CHECK-NEXT:      scf.yield %[[B]], %[[C]], %[[H]], %[[FALSE]] : vector<1x!qcc.qubit>, vector<1x!qcc.qubit>, vector<1x!qcc.qubit>, i1
// CHECK-NEXT:    }
// CHECK-NEXT:    qvec.single h %[[IF]]#0 : vector<1x!qcc.qubit>
// CHECK-NEXT:    return %[[IF]]#3 : i1

// -----

// `scf.if` has an else region whenever it has results: here one that passes the bound qubits on.
// CHECK-LABEL: func.func @if_without_else
// CHECK-SAME:  (%[[COND:.*]]: i1)
func.func @if_without_else(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  %q_out = qcf.if %cond (%a = %q) -> !qcc.qubit {
    %x = qcirc.single x %a : !qcc.qubit
    qcf.yield %x : !qcc.qubit
  }
  %h = qcirc.single h %q_out : !qcc.qubit
  return
}
// CHECK:         %[[Q:.*]] = qcc.static [0] : !qcc.qubit
// CHECK-NEXT:    %[[A:.*]] = vector.from_elements %[[Q]] : vector<1x!qcc.qubit>
// CHECK-NEXT:    %[[IF:.*]] = scf.if %[[COND]] -> (vector<1x!qcc.qubit>) {
// CHECK-NEXT:      %[[X:.*]] = qvec.single x %[[A]] : vector<1x!qcc.qubit>
// CHECK-NEXT:      scf.yield %[[X]] : vector<1x!qcc.qubit>
// CHECK-NEXT:    } else {
// CHECK-NEXT:      scf.yield %[[A]] : vector<1x!qcc.qubit>
// CHECK-NEXT:    }
// CHECK-NEXT:    qvec.single h %[[IF]] : vector<1x!qcc.qubit>
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
// CHECK:         %[[Q:.*]]:2 = qcc.static [0, 1] : !qcc.qubit
// CHECK-DAG:     %[[A:.*]] = vector.from_elements %[[Q]]#0 : vector<1x!qcc.qubit>
// CHECK-DAG:     %[[B:.*]] = vector.from_elements %[[Q]]#1 : vector<1x!qcc.qubit>
// CHECK:         scf.if %[[C0]] -> (vector<1x!qcc.qubit>, vector<1x!qcc.qubit>) {
// CHECK-NEXT:      %[[H:.*]] = qvec.single h %[[A]] : vector<1x!qcc.qubit>
// CHECK-NEXT:      %[[INNER:.*]] = scf.if %[[C1]] -> (vector<1x!qcc.qubit>) {
// CHECK-NEXT:        %[[X:.*]] = qvec.single x %[[B]] : vector<1x!qcc.qubit>
// CHECK-NEXT:        scf.yield %[[X]] : vector<1x!qcc.qubit>
// CHECK-NEXT:      } else {
// CHECK-NEXT:        scf.yield %[[B]] : vector<1x!qcc.qubit>
// CHECK-NEXT:      }
// CHECK-NEXT:      scf.yield %[[H]], %[[INNER]] : vector<1x!qcc.qubit>, vector<1x!qcc.qubit>
// CHECK-NEXT:    } else {
// CHECK-NEXT:      scf.yield %[[A]], %[[B]] : vector<1x!qcc.qubit>, vector<1x!qcc.qubit>
// CHECK-NEXT:    }
// CHECK-NEXT:    return
