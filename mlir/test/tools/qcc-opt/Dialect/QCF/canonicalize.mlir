// RUN: qcc-opt %s --canonicalize --split-input-file | FileCheck %s

// Trivial else region can be omitted.
func.func @trivial_else(%cond: i1) -> i1 {
  %q = qcc.static [0] : !qcc.qubit
  %r = qcf.if %cond (%a = %q) -> !qcc.qubit {
    %x = qcirc.single x %a : !qcc.qubit
    qcf.yield %x : !qcc.qubit
  } else (%a) {
    qcf.yield %a : !qcc.qubit
  }
  %r1, %bit = qcirc.measure z %r : !qcc.qubit -> i1
  return %bit : i1
}
// CHECK-LABEL: func.func @trivial_else
// CHECK:         qcf.if
// CHECK-NEXT:      qcirc.single x
// CHECK-NEXT:      qcf.yield
// CHECK-NEXT:    }{{$}}

// -----

// Not a trivial else (must not be omitted).
func.func @else_with_classical_result(%cond: i1) -> i1 {
  %q = qcc.static [0] : !qcc.qubit
  %r, %m = qcf.if %cond (%a = %q) -> (!qcc.qubit, i1) {
    %a1, %m1 = qcirc.measure z %a : !qcc.qubit -> i1
    qcf.yield %a1, %m1 : !qcc.qubit, i1
  } else (%a) {
    %false = arith.constant false
    qcf.yield %a, %false : !qcc.qubit, i1
  }
  return %m : i1
}
// CHECK-LABEL: func.func @else_with_classical_result
// CHECK:         qcf.if
// CHECK:         } else (

// -----

// Both branches are trivial and the whole qcf.if can be folded away.
func.func @identity(%cond: i1) -> i1 {
  %q = qcc.static [0] : !qcc.qubit
  %r = qcf.if %cond (%a = %q) -> !qcc.qubit {
    qcf.yield %a : !qcc.qubit
  } else (%a) {
    qcf.yield %a : !qcc.qubit
  }
  %r1, %bit = qcirc.measure z %r : !qcc.qubit -> i1
  return %bit : i1
}
// CHECK-LABEL: func.func @identity
// CHECK:         %[[Q:.*]] = qcc.static [0] : !qcc.qubit
// CHECK-NEXT:    %{{.*}}, %[[BIT:.*]] = qcirc.measure z %[[Q]] : !qcc.qubit -> i1
// CHECK-NEXT:    return %[[BIT]] : i1

// -----

// A qcf.if without results is dead.
func.func @identity_without_results(%cond: i1) {
  qcf.if %cond {
    qcf.yield
  }
  return
}
// CHECK-LABEL: func.func @identity_without_results
// CHECK-NEXT:    return

// -----

// A qcf.if with a provably true condition should be replaced by the then branch.
func.func @constant_true() -> i1 {
  %true = arith.constant true
  %q = qcc.static [0] : !qcc.qubit
  %r, %m = qcf.if %true (%a = %q) -> (!qcc.qubit, i1) {
    %a1, %m1 = qcirc.measure z %a : !qcc.qubit -> i1
    qcf.yield %a1, %m1 : !qcc.qubit, i1
  } else (%a) {
    %false = arith.constant false
    qcf.yield %a, %false : !qcc.qubit, i1
  }
  return %m : i1
}
// CHECK-LABEL: func.func @constant_true
// CHECK:         %[[Q:.*]] = qcc.static [0] : !qcc.qubit
// CHECK-NEXT:    %{{.*}}, %[[M:.*]] = qcirc.measure z %[[Q]] : !qcc.qubit -> i1
// CHECK-NEXT:    return %[[M]] : i1

// -----

// A qcf.if with a provably false condition should be replaced by the else branch.
func.func @constant_false() -> i1 {
  %false = arith.constant false
  %q = qcc.static [0] : !qcc.qubit
  %r = qcf.if %false (%a = %q) -> !qcc.qubit {
    %x = qcirc.single x %a : !qcc.qubit
    qcf.yield %x : !qcc.qubit
  } else (%a) {
    %h = qcirc.single h %a : !qcc.qubit
    qcf.yield %h : !qcc.qubit
  }
  %r1, %bit = qcirc.measure z %r : !qcc.qubit -> i1
  return %bit : i1
}
// CHECK-LABEL: func.func @constant_false
// CHECK:         %[[Q:.*]] = qcc.static [0] : !qcc.qubit
// CHECK-NEXT:    %[[H:.*]] = qcirc.single h %[[Q]] : !qcc.qubit
// CHECK-NEXT:    %{{.*}}, %[[BIT:.*]] = qcirc.measure z %[[H]] : !qcc.qubit -> i1
// CHECK-NEXT:    return %[[BIT]] : i1

// -----

// A qcf.if without else on a provably false condition is trivial and can be eliminated.
func.func @constant_false_without_else() -> i1 {
  %false = arith.constant false
  %q = qcc.static [0] : !qcc.qubit
  %r = qcf.if %false (%a = %q) -> !qcc.qubit {
    %x = qcirc.single x %a : !qcc.qubit
    qcf.yield %x : !qcc.qubit
  }
  %r1, %bit = qcirc.measure z %r : !qcc.qubit -> i1
  return %bit : i1
}
// CHECK-LABEL: func.func @constant_false_without_else
// CHECK:         %[[Q:.*]] = qcc.static [0] : !qcc.qubit
// CHECK-NEXT:    %{{.*}}, %[[BIT:.*]] = qcirc.measure z %[[Q]] : !qcc.qubit -> i1
// CHECK-NEXT:    return %[[BIT]] : i1

// -----

func.func private @effect()

// A qcf.if without bindings becomes an scf.if.
func.func @if_without_bindings(%c0: i1, %c1: i1, %a: i32, %b: i32) -> i32 {
  %r = qcf.if %c0 -> i32 {
    %s = arith.addi %a, %b : i32
    qcf.yield %s : i32
  } else {
    qcf.yield %a : i32
  }
  // without else region:
  qcf.if %c1 {
    func.call @effect() : () -> ()
    qcf.yield
  }
  return %r : i32
}
// CHECK-LABEL: func.func @if_without_bindings
// CHECK-SAME:  (%[[C0:.*]]: i1, %[[C1:.*]]: i1, %[[A:.*]]: i32, %[[B:.*]]: i32) -> i32
// CHECK-NEXT:    %[[R:.*]] = scf.if %[[C0]] -> (i32) {
// CHECK-NEXT:      %[[S:.*]] = arith.addi %[[A]], %[[B]] : i32
// CHECK-NEXT:      scf.yield %[[S]] : i32
// CHECK-NEXT:    } else {
// CHECK-NEXT:      scf.yield %[[A]] : i32
// CHECK-NEXT:    }
// CHECK-NEXT:    scf.if %[[C1]] {
// CHECK-NEXT:      func.call @effect() : () -> ()
// CHECK-NEXT:    }
// CHECK-NEXT:    return %[[R]] : i32
