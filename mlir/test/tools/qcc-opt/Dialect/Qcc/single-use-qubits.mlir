// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// The `SingleUseQubits` trait, on the ops that carry it: `qcc.static` and the `qcirc` ops.

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

// -----

func.func @nested_region(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  scf.if %cond {
    // expected-error @+1 {{'qcirc.single' op must be directly inside a function}}
    %h = qcirc.single h %q : !qcc.qubit
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
