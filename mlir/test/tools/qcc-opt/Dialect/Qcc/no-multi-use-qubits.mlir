// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// The `NoMultiUseQubits` trait, on the ops that carry it: `qcc.static`, the `qcirc` ops and the `qcf` ops.

// A qubit may go unused, and an op of another dialect may consume it.
func.func @valid() -> i1 {
  %q0, %q1, %q2, %q3 = qcc.static [0, 1, 2, 3] : !qcc.qubit
  %h = qcirc.single h %q0 : !qcc.qubit
  %c, %t = qcirc.pair cx %h, %q1 : !qcc.qubit
  %m, %bit = qcirc.measure z %c : !qcc.qubit -> i1
  %qs = vector.from_elements %t, %q2 : vector<2x!qcc.qubit>
  return %bit : i1
}

// Every function has qubits of its own.
func.func @valid_too() {
  %q0 = qcc.static [0] : !qcc.qubit
  return
}

// Unlike a qubit result, a vector result may be used several times: e.g. to take it apart.
func.func @vector_result_taken_apart(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  // We use qcf.if here because, at the time of writing this, it is the only op with the NoMultiUseQubits trait that
  // produces vectors of qubits.
  %v_out = qcf.if %cond (%a = %v) -> vector<2x!qcc.qubit> {
    qcf.yield %a : vector<2x!qcc.qubit>
  }
  %e0 = vector.extract %v_out[0] : !qcc.qubit from vector<2x!qcc.qubit>
  %e1 = vector.extract %v_out[1] : !qcc.qubit from vector<2x!qcc.qubit>
  return
}

// -----

func.func @nested_region(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  scf.if %cond {
    // expected-error @+1 {{'qcirc.single' op must be directly inside a function or a qubit scope}}
    %h = qcirc.single h %q : !qcc.qubit
  }
  return
}

// -----

// Inside a qubit scope, but not directly: the parent of the inner `qcf.if` is no qubit scope.
func.func @nested_region_in_qubit_scope(%c0: i1, %c1: i1, %c2: i1) {
  qcf.if %c0 {
    scf.if %c1 {
      // expected-error @+1 {{'qcf.if' op must be directly inside a function or a qubit scope}}
      qcf.if %c2 {
        qcf.yield
      }
    }
    qcf.yield
  }
  return
}

// -----

func.func @two_blocks() {
  // expected-error @+1 {{'qcc.static' op must be in a single-block function}}
  %q = qcc.static [0] : !qcc.qubit
  cf.br ^bb1
^bb1:
  return
}

// -----

func.func @qubit_argument(%q: !qcc.qubit) {
  // expected-error @+1 {{'qcirc.single' op must be in a function without qubit arguments and results}}
  %h = qcirc.single h %q : !qcc.qubit
  return
}

// -----

// The op need not touch the argument.
func.func @qubit_vector_argument(%qs: vector<2x!qcc.qubit>) {
  // expected-error @+1 {{'qcc.static' op must be in a function without qubit arguments and results}}
  %q = qcc.static [0] : !qcc.qubit
  return
}

// -----

func.func @qubit_result() -> !qcc.qubit {
  // expected-error @+1 {{'qcc.static' op must be in a function without qubit arguments and results}}
  %q = qcc.static [0] : !qcc.qubit
  return %q : !qcc.qubit
}

// -----

func.func @result_used_twice() {
  // expected-error @+1 {{'qcc.static' op qubit result #0 has 2 uses, but qubit values are affine}}
  %q = qcc.static [0] : !qcc.qubit
  %a = qcirc.single h %q : !qcc.qubit
  %b = qcirc.single x %q : !qcc.qubit
  return
}

// -----

// The qubits of one op are distinct.
func.func @result_used_twice_by_one_op() {
  // expected-error @+1 {{'qcc.static' op qubit result #1 has 2 uses, but qubit values are affine}}
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %a, %b = qcirc.pair cx %q1, %q1 : !qcc.qubit
  return
}

// -----

// A use by an op of another dialect counts as well.
func.func @result_used_by_foreign_op() {
  // expected-error @+1 {{'qcc.static' op qubit result #0 has 2 uses, but qubit values are affine}}
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %a = qcirc.single h %q0 : !qcc.qubit
  %qs = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  return
}

// -----

// A qubit from an op of another dialect: only its consumer can see the second use.
func.func @operand_used_twice() {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %qs = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  %e = vector.extract %qs[0] : !qcc.qubit from vector<2x!qcc.qubit>
  // expected-error @+1 {{'qcirc.single' op qubit operand #0 has 2 uses, but qubit values are affine}}
  %a = qcirc.single h %e : !qcc.qubit
  %b = qcirc.single x %e : !qcc.qubit
  return
}

// -----

// A vector operand is consumed as a whole: no other use. Here qubit 0 would be used twice: in the `qcf.if` and by the
// gate after it.
func.func @vector_operand_used_twice(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  %e = vector.extract %v[0] : !qcc.qubit from vector<2x!qcc.qubit>
  // expected-error @+1 {{'qcf.if' op qubit operand #0 has 2 uses, but qubit values are affine}}
  %r = qcf.if %cond (%a = %v) -> vector<2x!qcc.qubit> {
    qcf.yield %a : vector<2x!qcc.qubit>
  }
  %h = qcirc.single h %e : !qcc.qubit
  return
}

// -----

func.func @yield_operand_used_twice(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %r0, %r1 = qcf.if %cond (%a = %q0, %b = %q1) -> (!qcc.qubit, !qcc.qubit) {
    %v = vector.from_elements %a, %b : vector<2x!qcc.qubit>
    %e = vector.extract %v[0] : !qcc.qubit from vector<2x!qcc.qubit>
    // expected-error @+1 {{'qcf.yield' op qubit operand #0 has 2 uses, but qubit values are affine}}
    qcf.yield %e, %e : !qcc.qubit, !qcc.qubit
  }
  return
}
