// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// The `QubitScope` trait, on `qcf.if`.

func.func @capture(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-note @+1 {{qubit scope here}}
  %r = qcf.if %cond (%a = %q0) -> !qcc.qubit {
    // expected-error @+1 {{'qcirc.pair' op illegal capture of qubit operand #1}}
    %a1, %b1 = qcirc.pair cx %a, %q1 : !qcc.qubit
    qcf.yield %a1 : !qcc.qubit
  }
  return
}

// -----

// A capture at any depth counts.
func.func @capture_in_nested_region(%c0: i1, %c1: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-note @+1 {{qubit scope here}}
  qcf.if %c0 {
    scf.if %c1 {
      // expected-error @+1 {{'vector.from_elements' op illegal capture of qubit operand #0}}
      %v = vector.from_elements %q : vector<1x!qcc.qubit>
    }
    qcf.yield
  }
  return
}

// -----

// A nested qubit scope reports a capture in its own regions.
func.func @capture_in_nested_scope(%c0: i1, %c1: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %r = qcf.if %c0 (%a = %q0) -> !qcc.qubit {
    // expected-note @+1 {{qubit scope here}}
    %a1 = qcf.if %c1 (%x = %a) -> !qcc.qubit {
      // expected-error @+1 {{'qcirc.pair' op illegal capture of qubit operand #1}}
      %x1, %y1 = qcirc.pair cx %x, %q1 : !qcc.qubit
      qcf.yield %x1 : !qcc.qubit
    }
    qcf.yield %a1 : !qcc.qubit
  }
  return
}

// -----

// Binding a qubit from outside to a nested qubit scope is a capture by the enclosing scope.
func.func @capture_by_nested_binding(%c0: i1, %c1: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-note @+1 {{qubit scope here}}
  qcf.if %c0 {
    // expected-error @+1 {{'qcf.if' op illegal capture of qubit operand #0}}
    %x_out = qcf.if %c1 (%x = %q) -> !qcc.qubit {
      qcf.yield %x : !qcc.qubit
    }
    qcf.yield
  }
  return
}

// -----

// The binding of an enclosing scope is from outside, too.
func.func @capture_of_outer_binding(%c0: i1, %c1: i1) {
  %q = qcc.static [0] : !qcc.qubit
  %v = vector.from_elements %q : vector<1x!qcc.qubit>
  %r = qcf.if %c0 (%a = %v) -> vector<1x!qcc.qubit> {
    // expected-note @+1 {{qubit scope here}}
    qcf.if %c1 {
      // expected-error @+1 {{'vector.extract' op illegal capture of qubit operand #0}}
      %e = vector.extract %a[0] : !qcc.qubit from vector<1x!qcc.qubit>
      qcf.yield
    }
    qcf.yield %a : vector<1x!qcc.qubit>
  }
  return
}

// -----

func.func @binding_used_twice(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcf.if' op qubit binding #0 of region #1 has 2 uses, but qubit values are affine}}
  %r = qcf.if %cond (%a = %q) -> !qcc.qubit {
    qcf.yield %a : !qcc.qubit
  } else {
    %h = qcirc.single h %a : !qcc.qubit
    %v = vector.from_elements %a : vector<1x!qcc.qubit>
    qcf.yield %h : !qcc.qubit
  }
  return
}

// -----

func.func @empty_block(%cond: i1) {
  // expected-error @+1 {{'qcf.if' op expects a non-empty block}}
  "qcf.if"(%cond) ({
  ^bb0:
  }, {
  }) : (i1) -> ()
  return
}
