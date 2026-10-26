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
