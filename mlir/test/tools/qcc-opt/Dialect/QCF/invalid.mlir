// RUN: qcc-opt %s --split-input-file --verify-diagnostics

func.func @types_per_binding(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // One type per qubit, unlike in `qcirc`.
  // expected-error @+1 {{expected a result type for each binding, got 1 result type(s) for 2 binding(s)}}
  %r0, %r1 = qcf.if %cond (%a = %q0, %b = %q1) -> !qcc.qubit {
    qcf.yield %a, %b : !qcc.qubit, !qcc.qubit
  }
  return
}

// -----

func.func @qubit_without_binding(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{result #1 is a qubit without a binding: qubits leave only through the bindings}}
  %r0, %r1 = qcf.if %cond (%a = %q) -> (!qcc.qubit, !qcc.qubit) {
    qcf.yield %a : !qcc.qubit
  }
  return
}

// -----

func.func @classical_result_without_else(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcf.if' op must have an else region if it has classical results}}
  %r, %m = qcf.if %cond (%a = %q) -> (!qcc.qubit, i1) {
    %a1, %m1 = qcirc.measure z %a : !qcc.qubit -> i1
    qcf.yield %a1, %m1 : !qcc.qubit, i1
  }
  return
}

// -----

func.func @wrong_terminator(%cond: i1) {
  // expected-error @+1 {{'qcf.if' op expects region #0 to end with 'qcf.yield'}}
  qcf.if %cond {
    llvm.unreachable
  }
  return
}

// -----

// The region branch interface matches the bound qubits with the arguments of each region.
func.func @region_arguments(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+2 {{'qcf.if' op along control flow edge from parent to Region #0: region branch point has 1 operands, but region successor needs 2 inputs}}
  // expected-note @+1 {{region branch point}}
  %r = "qcf.if"(%q, %cond) ({
  ^bb0(%a: !qcc.qubit, %b: !qcc.qubit):
    "qcf.yield"(%a) : (!qcc.qubit) -> ()
  }, {
  }) : (!qcc.qubit, i1) -> (!qcc.qubit)
  return
}

// -----

// ... and the operands of each yield with the results.
func.func @yield_count(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcf.if' op along control flow edge from Operation qcf.yield to Operation qcf.if: region branch point has 0 operands, but region successor needs 1 inputs}}
  %r = qcf.if %cond (%a = %q) -> !qcc.qubit {
    // expected-note @+1 {{region branch point}}
    qcf.yield
  }
  return
}

// -----

//===----------------------------------------------------------------------===//
// The qubit bound to argument i is yielded at position i.
//===----------------------------------------------------------------------===//

func.func @yield_swapped(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'qcf.if' op region #0 yields the qubit bound to argument #1 at position #0, but a bound qubit must be yielded at the position of its binding}}
  %r0, %r1 = qcf.if %cond (%a = %q0, %b = %q1) -> (!qcc.qubit, !qcc.qubit) {
    // expected-note @+1 {{yielded here}}
    qcf.yield %b, %a : !qcc.qubit, !qcc.qubit
  }
  return
}

// -----

// The check walks back through lane ops; a swap exchanges states, not lanes.
func.func @yield_swapped_through_gates(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'qcf.if' op region #1 yields the qubit bound to argument #1 at position #0}}
  %r0, %r1 = qcf.if %cond (%a = %q0, %b = %q1) -> (!qcc.qubit, !qcc.qubit) {
    qcf.yield %a, %b : !qcc.qubit, !qcc.qubit
  } else {
    %b1, %a1 = qcirc.pair swap %b, %a : !qcc.qubit
    %b2, %m = qcirc.measure z %b1 : !qcc.qubit -> i1
    %b3 = qcirc.single h %b2 : !qcc.qubit
    // expected-note @+1 {{yielded here}}
    qcf.yield %b3, %a1 : !qcc.qubit, !qcc.qubit
  }
  return
}

// -----

// ... and through a nested `qcf.if`.
func.func @yield_swapped_through_if(%c0: i1, %c1: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'qcf.if' op region #0 yields the qubit bound to argument #1 at position #0}}
  %r0, %r1 = qcf.if %c0 (%a = %q0, %b = %q1) -> (!qcc.qubit, !qcc.qubit) {
    %b1, %a1 = qcf.if %c1 (%x = %b, %y = %a) -> (!qcc.qubit, !qcc.qubit) {
      qcf.yield %x, %y : !qcc.qubit, !qcc.qubit
    }
    // expected-note @+1 {{yielded here}}
    qcf.yield %b1, %a1 : !qcc.qubit, !qcc.qubit
  }
  return
}
