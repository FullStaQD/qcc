// RUN: qcc-opt %s | FileCheck %s
// RUN: qcc-opt %s --mlir-print-op-generic | qcc-opt | FileCheck %s

// The else region has the same arguments as the then region, printed once in the binding list.
func.func @if_else() -> i1 {
  %a_in, %b_in, %c = qcc.static [0, 1, 2] : !qcc.qubit
  %c1, %bit = qcirc.measure z %c : !qcc.qubit -> i1

  %a_out, %b_out, %m = qcf.if %bit (%a = %a_in, %b = %b_in) : !qcc.qubit, !qcc.qubit => i1 {
    %a1, %b1 = qcirc.pair cx %a, %b : !qcc.qubit
    %b2, %m1 = qcirc.measure z %b1 : !qcc.qubit -> i1
    qcf.yield %a1, %b2, %m1 : !qcc.qubit, !qcc.qubit, i1
  } else {
    %false = arith.constant false
    qcf.yield %a, %b, %false : !qcc.qubit, !qcc.qubit, i1
  }

  return %m : i1
}
// CHECK-LABEL: func.func @if_else
// CHECK:         %[[Q:.*]]:3 = qcc.static [0, 1, 2] : !qcc.qubit
// CHECK-NEXT:    %{{.*}}, %[[BIT:.*]] = qcirc.measure z %[[Q]]#2 : !qcc.qubit -> i1
// CHECK-NEXT:    %[[IF:.*]]:3 = qcf.if %[[BIT]] (%[[A:.*]] = %[[Q]]#0, %[[B:.*]] = %[[Q]]#1) : !qcc.qubit, !qcc.qubit => i1 {
// CHECK-NEXT:      %[[A1:.*]], %[[B1:.*]] = qcirc.pair cx %[[A]], %[[B]] : !qcc.qubit
// CHECK-NEXT:      %[[B2:.*]], %[[M1:.*]] = qcirc.measure z %[[B1]] : !qcc.qubit -> i1
// CHECK-NEXT:      qcf.yield %[[A1]], %[[B2]], %[[M1]] : !qcc.qubit, !qcc.qubit, i1
// CHECK-NEXT:    } else {
// CHECK-NEXT:      %[[FALSE:.*]] = arith.constant false
// CHECK-NEXT:      qcf.yield %[[A]], %[[B]], %[[FALSE]] : !qcc.qubit, !qcc.qubit, i1
// CHECK-NEXT:    }
// CHECK-NEXT:    return %[[IF]]#2 : i1

// Without classical results the else region may be omitted: it would yield the bound qubits unchanged.
func.func @if_without_else(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  %q_out = qcf.if %cond (%a = %q) : !qcc.qubit {
    %x = qcirc.single x %a : !qcc.qubit
    qcf.yield %x : !qcc.qubit
  }
  return
}
// CHECK-LABEL: func.func @if_without_else
// CHECK-SAME:  (%[[COND:.*]]: i1)
// CHECK:         %[[Q:.*]] = qcc.static [0] : !qcc.qubit
// CHECK-NEXT:    %{{.*}} = qcf.if %[[COND]] (%[[A:.*]] = %[[Q]]) : !qcc.qubit {
// CHECK-NEXT:      %[[X:.*]] = qcirc.single x %[[A]] : !qcc.qubit
// CHECK-NEXT:      qcf.yield %[[X]] : !qcc.qubit
// CHECK-NEXT:    }
// CHECK-NEXT:    return

func.func @without_bindings(%cond: i1, %value: i32) -> i32 {
  %r = qcf.if %cond => i32 {
    qcf.yield %value : i32
  } else {
    %zero = arith.constant 0 : i32
    qcf.yield %zero : i32
  }
  qcf.if %cond {
    qcf.yield
  }
  return %r : i32
}
// CHECK-LABEL: func.func @without_bindings
// CHECK-SAME:  (%[[COND:.*]]: i1, %[[VALUE:.*]]: i32) -> i32
// CHECK:         %[[IF:.*]] = qcf.if %[[COND]] => i32 {
// CHECK-NEXT:      qcf.yield %[[VALUE]] : i32
// CHECK-NEXT:    } else {
// CHECK-NEXT:      %[[ZERO:.*]] = arith.constant 0 : i32
// CHECK-NEXT:      qcf.yield %[[ZERO]] : i32
// CHECK-NEXT:    }
// CHECK-NEXT:    qcf.if %[[COND]] {
// CHECK-NEXT:      qcf.yield{{$}}
// CHECK-NEXT:    }
// CHECK-NEXT:    return %[[IF]] : i32

// Classical values may be captured; several classical results follow the qubits.
func.func @classical_capture(%cond: i1, %theta: f64) -> (i1, f64) {
  %q = qcc.static [0] : !qcc.qubit
  %q_out, %flag, %angle = qcf.if %cond (%a = %q) : !qcc.qubit => i1, f64 {
    %rz = qcirc.single rz(%theta) %a : f64, !qcc.qubit
    qcf.yield %rz, %cond, %theta : !qcc.qubit, i1, f64
  } else {
    qcf.yield %a, %cond, %theta : !qcc.qubit, i1, f64
  }
  return %flag, %angle : i1, f64
}
// CHECK-LABEL: func.func @classical_capture
// CHECK-SAME:  (%[[COND:.*]]: i1, %[[THETA:.*]]: f64) -> (i1, f64)
// CHECK:         %[[Q:.*]] = qcc.static [0] : !qcc.qubit
// CHECK-NEXT:    %[[IF:.*]]:3 = qcf.if %[[COND]] (%[[A:.*]] = %[[Q]]) : !qcc.qubit => i1, f64 {
// CHECK-NEXT:      %[[RZ:.*]] = qcirc.single rz(%[[THETA]]) %[[A]] : f64, !qcc.qubit
// CHECK-NEXT:      qcf.yield %[[RZ]], %[[COND]], %[[THETA]] : !qcc.qubit, i1, f64
// CHECK-NEXT:    } else {
// CHECK-NEXT:      qcf.yield %[[A]], %[[COND]], %[[THETA]] : !qcc.qubit, i1, f64
// CHECK-NEXT:    }
// CHECK-NEXT:    return %[[IF]]#1, %[[IF]]#2 : i1, f64

// A lane follows the qubit, not its state: after the swap `%a1` is still the qubit bound to `%a`.
func.func @lanes_through_swap(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %r0, %r1 = qcf.if %cond (%a = %q0, %b = %q1) : !qcc.qubit, !qcc.qubit {
    %a1, %b1 = qcirc.pair swap %a, %b : !qcc.qubit
    qcf.yield %a1, %b1 : !qcc.qubit, !qcc.qubit
  }
  return
}
// CHECK-LABEL: func.func @lanes_through_swap
// CHECK-SAME:  (%[[COND:.*]]: i1)
// CHECK:         %[[Q:.*]]:2 = qcc.static [0, 1] : !qcc.qubit
// CHECK-NEXT:    %{{.*}}:2 = qcf.if %[[COND]] (%[[A:.*]] = %[[Q]]#0, %[[B:.*]] = %[[Q]]#1) : !qcc.qubit, !qcc.qubit {
// CHECK-NEXT:      %[[A1:.*]], %[[B1:.*]] = qcirc.pair swap %[[A]], %[[B]] : !qcc.qubit
// CHECK-NEXT:      qcf.yield %[[A1]], %[[B1]] : !qcc.qubit, !qcc.qubit
// CHECK-NEXT:    }
// CHECK-NEXT:    return

// A vector binding may be taken apart. The check of the yield walks back from a yielded qubit along its lane and
// stops silently at an op that is not a lane op, here `vector.from_elements`.
//
// TODO: VERIFICATION GAP. The position rule holds per element, but nothing checks the elements of a vector binding.
// Yielding `vector.from_elements %h, %e0` (elements swapped), or trading an element for the scalar binding `%s`,
// passes the verifier, yet is invalid IR. Closing the gap needs an element-wise analysis. It is not yet decided if or
// how we are actually going to close the gap.
func.func @vector_bindings(%cond: i1) {
  %q0, %q1, %q2 = qcc.static [0, 1, 2] : !qcc.qubit
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  %v_out, %s_out = qcf.if %cond (%vb = %v, %s = %q2) : vector<2x!qcc.qubit>, !qcc.qubit {
    %e0 = vector.extract %vb[0] : !qcc.qubit from vector<2x!qcc.qubit>
    %e1 = vector.extract %vb[1] : !qcc.qubit from vector<2x!qcc.qubit>
    %h = qcirc.single h %e1 : !qcc.qubit
    %w = vector.from_elements %e0, %h : vector<2x!qcc.qubit>
    %s1 = qcirc.single x %s : !qcc.qubit
    qcf.yield %w, %s1 : vector<2x!qcc.qubit>, !qcc.qubit
  } else {
    qcf.yield %vb, %s : vector<2x!qcc.qubit>, !qcc.qubit
  }
  return
}
// CHECK-LABEL: func.func @vector_bindings
// CHECK-SAME:  (%[[COND:.*]]: i1)
// CHECK:         %[[Q:.*]]:3 = qcc.static [0, 1, 2] : !qcc.qubit
// CHECK-NEXT:    %[[V:.*]] = vector.from_elements %[[Q]]#0, %[[Q]]#1 : vector<2x!qcc.qubit>
// CHECK-NEXT:    %{{.*}}:2 = qcf.if %[[COND]] (%[[VB:.*]] = %[[V]], %[[S:.*]] = %[[Q]]#2) : vector<2x!qcc.qubit>, !qcc.qubit {
// CHECK-NEXT:      %[[E0:.*]] = vector.extract %[[VB]][0] : !qcc.qubit from vector<2x!qcc.qubit>
// CHECK-NEXT:      %[[E1:.*]] = vector.extract %[[VB]][1] : !qcc.qubit from vector<2x!qcc.qubit>
// CHECK-NEXT:      %[[H:.*]] = qcirc.single h %[[E1]] : !qcc.qubit
// CHECK-NEXT:      %[[W:.*]] = vector.from_elements %[[E0]], %[[H]] : vector<2x!qcc.qubit>
// CHECK-NEXT:      %[[S1:.*]] = qcirc.single x %[[S]] : !qcc.qubit
// CHECK-NEXT:      qcf.yield %[[W]], %[[S1]] : vector<2x!qcc.qubit>, !qcc.qubit
// CHECK-NEXT:    } else {
// CHECK-NEXT:      qcf.yield %[[VB]], %[[S]] : vector<2x!qcc.qubit>, !qcc.qubit
// CHECK-NEXT:    }
// CHECK-NEXT:    return

// A nested `qcf.if` is a lane op like a gate, and a qubit scope for the ops in its regions. The outer yield is
// checked through it: `%a1` is the qubit bound to `%a`.
func.func @nested(%c0: i1, %c1: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %r0, %r1 = qcf.if %c0 (%a = %q0, %b = %q1) : !qcc.qubit, !qcc.qubit {
    %b1, %a1 = qcf.if %c1 (%x = %b, %y = %a) : !qcc.qubit, !qcc.qubit {
      %x1, %y1 = qcirc.pair cz %x, %y : !qcc.qubit
      qcf.yield %x1, %y1 : !qcc.qubit, !qcc.qubit
    }
    qcf.yield %a1, %b1 : !qcc.qubit, !qcc.qubit
  }
  return
}
// CHECK-LABEL: func.func @nested
// CHECK-SAME:  (%[[C0:.*]]: i1, %[[C1:.*]]: i1)
// CHECK:         %[[Q:.*]]:2 = qcc.static [0, 1] : !qcc.qubit
// CHECK-NEXT:    %{{.*}}:2 = qcf.if %[[C0]] (%[[A:.*]] = %[[Q]]#0, %[[B:.*]] = %[[Q]]#1) : !qcc.qubit, !qcc.qubit {
// CHECK-NEXT:      %[[INNER:.*]]:2 = qcf.if %[[C1]] (%[[X:.*]] = %[[B]], %[[Y:.*]] = %[[A]]) : !qcc.qubit, !qcc.qubit {
// CHECK-NEXT:        %[[X1:.*]], %[[Y1:.*]] = qcirc.pair cz %[[X]], %[[Y]] : !qcc.qubit
// CHECK-NEXT:        qcf.yield %[[X1]], %[[Y1]] : !qcc.qubit, !qcc.qubit
// CHECK-NEXT:      }
// CHECK-NEXT:      qcf.yield %[[INNER]]#1, %[[INNER]]#0 : !qcc.qubit, !qcc.qubit
// CHECK-NEXT:    }
// CHECK-NEXT:    return

func.func @attributes(%cond: i1) {
  qcf.if %cond {
    qcf.yield
  } {some_attr}
  return
}
// CHECK-LABEL: func.func @attributes
// CHECK-SAME:  (%[[COND:.*]]: i1)
// CHECK:         qcf.if %[[COND]] {
// CHECK-NEXT:      qcf.yield
// CHECK-NEXT:    } {some_attr}
// CHECK-NEXT:    return
