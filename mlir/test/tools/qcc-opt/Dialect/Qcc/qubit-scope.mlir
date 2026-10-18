// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// The `QubitScope` trait, on `qcf.if`.

// A vector binding may be used several times (taken apart), a classical value may be captured.
func.func @valid(%cond: i1, %theta: f64) {
  %q0, %q1, %q2 = qcc.static [0, 1, 2] : !qcc.qubit
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  %v_out, %s_out = qcf.if %cond (%vb = %v, %s = %q2) -> (vector<2x!qcc.qubit>, !qcc.qubit) {
    %e0 = vector.extract %vb[0] : !qcc.qubit from vector<2x!qcc.qubit>
    %e1 = vector.extract %vb[1] : !qcc.qubit from vector<2x!qcc.qubit>
    %rz = qcirc.single rz(%theta) %s : f64, !qcc.qubit
    %w = vector.from_elements %e0, %e1 : vector<2x!qcc.qubit>
    qcf.yield %w, %rz : vector<2x!qcc.qubit>, !qcc.qubit
  }
  return
}

// -----

func.func @capture(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'qcf.if' op captures a qubit, but qubits enter a qubit scope only through its bindings}}
  %r = qcf.if %cond (%a = %q0) -> !qcc.qubit {
    // expected-note @+1 {{operand #1 is from outside}}
    %a1, %b1 = qcirc.pair cx %a, %q1 : !qcc.qubit
    qcf.yield %a1 : !qcc.qubit
  }
  return
}

// -----

// A capture by an op of another dialect counts as well, and so does a vector.
func.func @capture_vector_by_foreign_op(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  // expected-error @+1 {{'qcf.if' op captures a qubit}}
  qcf.if %cond {
    // expected-note @+1 {{operand #0 is from outside}}
    %e = vector.extract %v[0] : !qcc.qubit from vector<2x!qcc.qubit>
    qcf.yield
  }
  return
}

// -----

// A capture at any depth counts.
func.func @capture_in_nested_region(%c0: i1, %c1: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcf.if' op captures a qubit}}
  qcf.if %c0 {
    scf.if %c1 {
      // expected-note @+1 {{operand #0 is from outside}}
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
    // expected-error @+1 {{'qcf.if' op captures a qubit}}
    %a1 = qcf.if %c1 (%x = %a) -> !qcc.qubit {
      // expected-note @+1 {{operand #1 is from outside}}
      %x1, %y1 = qcirc.pair cx %x, %q1 : !qcc.qubit
      qcf.yield %x1 : !qcc.qubit
    }
    qcf.yield %a1 : !qcc.qubit
  }
  return
}

// -----

// The binding of an enclosing scope is from outside, too.
func.func @capture_of_outer_binding(%c0: i1, %c1: i1) {
  %q = qcc.static [0] : !qcc.qubit
  %v = vector.from_elements %q : vector<1x!qcc.qubit>
  %r = qcf.if %c0 (%a = %v) -> vector<1x!qcc.qubit> {
    // expected-error @+1 {{'qcf.if' op captures a qubit}}
    qcf.if %c1 {
      // expected-note @+1 {{operand #0 is from outside}}
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

func.func @two_blocks(%cond: i1) {
  // expected-error @+1 {{'qcf.if' op expects region #1 to have 0 or 1 blocks}}
  "qcf.if"(%cond) ({
    "qcf.yield"() : () -> ()
  }, {
    cf.br ^bb1
  ^bb1:
    "qcf.yield"() : () -> ()
  }) : (i1) -> ()
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
