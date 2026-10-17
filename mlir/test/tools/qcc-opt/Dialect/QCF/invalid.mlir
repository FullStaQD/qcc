// RUN: qcc-opt %s --split-input-file --verify-diagnostics

func.func @types_per_binding(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // One type per qubit, unlike in `qcirc`.
  // expected-error @+1 {{expected one type per binding, got 1 type(s) for 2 binding(s)}}
  %r0, %r1 = qcf.if %cond (%a = %q0, %b = %q1) : !qcc.qubit {
    qcf.yield %a, %b : !qcc.qubit, !qcc.qubit
  }
  return
}

// -----

func.func @qubit_as_classical_result(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{a classical result must not be a qubit: qubits leave through the bindings}}
  %r0, %r1 = qcf.if %cond (%a = %q) : !qcc.qubit => !qcc.qubit {
    qcf.yield %a : !qcc.qubit
  }
  return
}

// -----

func.func @classical_binding(%cond: i1, %value: i32) {
  // expected-error @+1 {{'qcf.if' op operand #0 must be variadic of qubit or vector of qubits, but got 'i32'}}
  %r = qcf.if %cond (%a = %value) : i32 {
    qcf.yield %a : i32
  }
  return
}

// -----

func.func @condition_type(%cond: i32) {
  // expected-error @+2 {{use of value '%cond' expects different type than prior uses: 'i1' vs 'i32'}}
  // expected-note @-2 {{prior use here}}
  qcf.if %cond {
    qcf.yield
  }
  return
}

// -----

func.func @classical_result_without_else(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcf.if' op must have an else region if it has classical results}}
  %r, %m = qcf.if %cond (%a = %q) : !qcc.qubit => i1 {
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

func.func @yield_outside() {
  // expected-error @+1 {{'qcf.yield' op expects parent op 'qcf.if'}}
  qcf.yield
}

// -----

func.func @missing_then_region(%cond: i1) {
  // expected-error @+1 {{'qcf.if' op region #0 ('thenRegion') failed to verify constraint: region with 1 blocks}}
  "qcf.if"(%cond) ({
  }, {
  }) : (i1) -> ()
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
  %r = qcf.if %cond (%a = %q) : !qcc.qubit {
    // expected-note @+1 {{region branch point}}
    qcf.yield
  }
  return
}

// -----

func.func @yield_type(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcf.if' op along control flow edge from Operation qcf.yield to Operation qcf.if: successor operand type #1 'i32' should match successor input type #1 'i1'}}
  %r, %m = qcf.if %cond (%a = %q) : !qcc.qubit => i1 {
    %false = arith.constant false
    qcf.yield %a, %false : !qcc.qubit, i1
  } else {
    %zero = arith.constant 0 : i32
    // expected-note @+1 {{region branch point}}
    qcf.yield %a, %zero : !qcc.qubit, i32
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
  %r0, %r1 = qcf.if %cond (%a = %q0, %b = %q1) : !qcc.qubit, !qcc.qubit {
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
  %r0, %r1 = qcf.if %cond (%a = %q0, %b = %q1) : !qcc.qubit, !qcc.qubit {
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
  %r0, %r1 = qcf.if %c0 (%a = %q0, %b = %q1) : !qcc.qubit, !qcc.qubit {
    %b1, %a1 = qcf.if %c1 (%x = %b, %y = %a) : !qcc.qubit, !qcc.qubit {
      qcf.yield %x, %y : !qcc.qubit, !qcc.qubit
    }
    // expected-note @+1 {{yielded here}}
    qcf.yield %b1, %a1 : !qcc.qubit, !qcc.qubit
  }
  return
}

// -----

func.func @yield_swapped_vectors(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
  %v1 = vector.from_elements %q1 : vector<1x!qcc.qubit>
  // expected-error @+1 {{'qcf.if' op region #0 yields the qubit bound to argument #1 at position #0}}
  %r0, %r1 = qcf.if %cond (%a = %v0, %b = %v1) : vector<1x!qcc.qubit>, vector<1x!qcc.qubit> {
    // expected-note @+1 {{yielded here}}
    qcf.yield %b, %a : vector<1x!qcc.qubit>, vector<1x!qcc.qubit>
  }
  return
}
