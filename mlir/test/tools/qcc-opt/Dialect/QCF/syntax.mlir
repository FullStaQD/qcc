// RUN: qcc-opt %s | FileCheck %s
// RUN: qcc-opt %s --mlir-print-op-generic | qcc-opt | FileCheck %s

// CHECK-LABEL: func.func @if_else
func.func @if_else() -> i1 {
  // CHECK: %[[Q:.*]]:3 = qcc.static [0, 1, 2] : !qcc.qubit
  %a_in, %b_in, %c = qcc.static [0, 1, 2] : !qcc.qubit
  // CHECK: %{{.*}}, %[[BIT:.*]] = qcirc.measure z %[[Q]]#2
  %c1, %bit = qcirc.measure z %c : !qcc.qubit -> i1
  // CHECK: %[[IF:.*]]:3 = qcf.if %[[BIT]] (%[[A:.*]] = %[[Q]]#0, %[[B:.*]] = %[[Q]]#1) : !qcc.qubit, !qcc.qubit => i1 {
  %a_out, %b_out, %m = qcf.if %bit (%a = %a_in, %b = %b_in) : !qcc.qubit, !qcc.qubit => i1 {
    // CHECK-NEXT: %[[A1:.*]], %[[B1:.*]] = qcirc.pair cx %[[A]], %[[B]] : !qcc.qubit
    %a1, %b1 = qcirc.pair cx %a, %b : !qcc.qubit
    // CHECK-NEXT: %[[B2:.*]], %[[M1:.*]] = qcirc.measure z %[[B1]] : !qcc.qubit -> i1
    %b2, %m1 = qcirc.measure z %b1 : !qcc.qubit -> i1
    // CHECK-NEXT: qcf.yield %[[A1]], %[[B2]], %[[M1]] : !qcc.qubit, !qcc.qubit, i1
    qcf.yield %a1, %b2, %m1 : !qcc.qubit, !qcc.qubit, i1
  // The else region has the same arguments, printed once in the binding list.
  // CHECK-NEXT: } else {
  } else {
    // CHECK-NEXT: %[[FALSE:.*]] = arith.constant false
    %false = arith.constant false
    // CHECK-NEXT: qcf.yield %[[A]], %[[B]], %[[FALSE]] : !qcc.qubit, !qcc.qubit, i1
    qcf.yield %a, %b, %false : !qcc.qubit, !qcc.qubit, i1
  }
  // CHECK: return %[[IF]]#2
  return %m : i1
}

// Without classical results the else region may be omitted: it would yield the bound qubits unchanged.
// CHECK-LABEL: func.func @if_without_else
func.func @if_without_else(%cond: i1) {
  // CHECK: %[[Q:.*]] = qcc.static [0] : !qcc.qubit
  %q = qcc.static [0] : !qcc.qubit
  // CHECK: qcf.if %{{.*}} (%[[A:.*]] = %[[Q]]) : !qcc.qubit {
  %q_out = qcf.if %cond (%a = %q) : !qcc.qubit {
    // CHECK-NEXT: %[[X:.*]] = qcirc.single x %[[A]] : !qcc.qubit
    %x = qcirc.single x %a : !qcc.qubit
    // CHECK-NEXT: qcf.yield %[[X]] : !qcc.qubit
    qcf.yield %x : !qcc.qubit
  // CHECK-NEXT: }
  // CHECK-NEXT: return
  }
  return
}

// CHECK-LABEL: func.func @without_bindings
func.func @without_bindings(%cond: i1, %value: i32) -> i32 {
  // CHECK: %{{.*}} = qcf.if %{{.*}} => i32 {
  %r = qcf.if %cond => i32 {
    qcf.yield %value : i32
  } else {
    %zero = arith.constant 0 : i32
    qcf.yield %zero : i32
  }
  // CHECK: qcf.if %{{.*}} {
  // CHECK-NEXT: qcf.yield{{$}}
  // CHECK-NEXT: }
  qcf.if %cond {
    qcf.yield
  }
  return %r : i32
}

// Classical values may be captured; several classical results follow the qubits.
// CHECK-LABEL: func.func @classical_capture
// CHECK-SAME: (%[[COND:.*]]: i1, %[[THETA:.*]]: f64)
func.func @classical_capture(%cond: i1, %theta: f64) -> (i1, f64) {
  %q = qcc.static [0] : !qcc.qubit
  // CHECK: qcf.if %[[COND]] (%[[A:.*]] = %{{.*}}) : !qcc.qubit => i1, f64 {
  %q_out, %flag, %angle = qcf.if %cond (%a = %q) : !qcc.qubit => i1, f64 {
    // CHECK-NEXT: qcirc.single rz(%[[THETA]]) %[[A]] : f64, !qcc.qubit
    %rz = qcirc.single rz(%theta) %a : f64, !qcc.qubit
    qcf.yield %rz, %cond, %theta : !qcc.qubit, i1, f64
  } else {
    qcf.yield %a, %cond, %theta : !qcc.qubit, i1, f64
  }
  return %flag, %angle : i1, f64
}

// A lane follows the qubit, not its state: after the swap `%a1` is still the qubit bound to `%a`.
// CHECK-LABEL: func.func @lanes_through_swap
func.func @lanes_through_swap(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // CHECK: qcf.if
  %r0, %r1 = qcf.if %cond (%a = %q0, %b = %q1) : !qcc.qubit, !qcc.qubit {
    // CHECK-NEXT: %[[B1:.*]], %[[A1:.*]] = qcirc.pair swap
    %b1, %a1 = qcirc.pair swap %b, %a : !qcc.qubit
    // CHECK-NEXT: qcf.yield %[[A1]], %[[B1]]
    qcf.yield %a1, %b1 : !qcc.qubit, !qcc.qubit
  }
  return
}

// A vector binding may be taken apart. The check of the yield walks back from a yielded qubit along its lane and
// stops silently at an op that is not a lane op, here `vector.from_elements`.
// CHECK-LABEL: func.func @vector_bindings
func.func @vector_bindings(%cond: i1) {
  %q0, %q1, %q2 = qcc.static [0, 1, 2] : !qcc.qubit
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  // CHECK: qcf.if %{{.*}} (%[[V:.*]] = %{{.*}}, %[[S:.*]] = %{{.*}}) : vector<2x!qcc.qubit>, !qcc.qubit {
  %v_out, %s_out = qcf.if %cond (%vb = %v, %s = %q2) : vector<2x!qcc.qubit>, !qcc.qubit {
    // CHECK-NEXT: vector.extract %[[V]][0]
    // CHECK-NEXT: vector.extract %[[V]][1]
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

// A nested `qcf.if` is a lane op like a gate, and a qubit scope for the ops in its regions. The outer yield is
// checked through it: `%a1` is the qubit bound to `%a`.
// CHECK-LABEL: func.func @nested
func.func @nested(%c0: i1, %c1: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // CHECK: qcf.if %{{.*}} (%[[A:.*]] = %{{.*}}, %[[B:.*]] = %{{.*}}) : !qcc.qubit, !qcc.qubit {
  %r0, %r1 = qcf.if %c0 (%a = %q0, %b = %q1) : !qcc.qubit, !qcc.qubit {
    // CHECK-NEXT: %[[INNER:.*]]:2 = qcf.if %{{.*}} (%[[X:.*]] = %[[B]], %[[Y:.*]] = %[[A]]) : !qcc.qubit, !qcc.qubit {
    %b1, %a1 = qcf.if %c1 (%x = %b, %y = %a) : !qcc.qubit, !qcc.qubit {
      // CHECK-NEXT: %[[X1:.*]], %[[Y1:.*]] = qcirc.pair cz %[[X]], %[[Y]] : !qcc.qubit
      %x1, %y1 = qcirc.pair cz %x, %y : !qcc.qubit
      // CHECK-NEXT: qcf.yield %[[X1]], %[[Y1]] : !qcc.qubit, !qcc.qubit
      qcf.yield %x1, %y1 : !qcc.qubit, !qcc.qubit
    }
    // CHECK: qcf.yield %[[INNER]]#1, %[[INNER]]#0 : !qcc.qubit, !qcc.qubit
    qcf.yield %a1, %b1 : !qcc.qubit, !qcc.qubit
  }
  return
}

// CHECK-LABEL: func.func @attributes
func.func @attributes(%cond: i1) {
  // CHECK: qcf.if %{{.*}} {
  // CHECK-NEXT: qcf.yield
  // CHECK-NEXT: } {some_attr}
  qcf.if %cond {
    qcf.yield
  } {some_attr}
  return
}
