// RUN: qcc-opt %s --split-input-file --verify-diagnostics

func.func @missing_parameter() {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  // expected-error @+1 {{'qref.single' op gate 'rz' takes 1 parameter(s), got 0}}
  qref.single rz %q : !qcc.qubit_ref
  return
}

// -----

func.func @parameter_type(%theta: f32) {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  // expected-error @+1 {{'qref.single' op operand #1 must be variadic of 64-bit float angle, but got 'f32'}}
  qref.single rz(%theta) %q : f32, !qcc.qubit_ref
  return
}

// -----

// Value-semantics qubits belong to `qcirc`.
func.func @qubit_type() {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qref.single' op operand #0 must be reference to a qubit, but got '!qcc.qubit'}}
  qref.single h %q : !qcc.qubit
  return
}

// -----

func.func @pair_too_many_parameters(%theta: f64) {
  %q0, %q1 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  // expected-error @+1 {{'qref.pair' op gate 'cx' takes 0 parameter(s), got 1}}
  qref.pair cx(%theta) %q0, %q1 : f64, !qcc.qubit_ref
  return
}

// -----

func.func @pair_same_value(%q: !qcc.qubit_ref) {
  // expected-error @+1 {{'qref.pair' op requires distinct qubits, but lhs and rhs are the same value}}
  qref.pair cx %q, %q : !qcc.qubit_ref
  return
}

// -----

// Two references with the same static index name the same qubit.
func.func @pair_same_static_qubit() {
  %a = qcc.static_ref [1] : !qcc.qubit_ref
  %b = qcc.static_ref [1] : !qcc.qubit_ref
  // expected-error @+1 {{'qref.pair' op requires distinct qubits, but lhs and rhs both name static qubit 1}}
  qref.pair cz %a, %b : !qcc.qubit_ref
  return
}

// -----

// The pair is verified before the `qcc.static_ref` that defines its operands, which then has fewer indices than
// results. The pair must not read beyond the indices.
func.func @pair_on_unverified_static_ref() {
  qref.pair cx %a, %b : !qcc.qubit_ref
  // expected-error @+1 {{'qcc.static_ref' op expected one qubit per index, got 2 qubit(s) for 1 indices}}
  %a, %b = "qcc.static_ref"() <{indices = array<i64: 0>}> : () -> (!qcc.qubit_ref, !qcc.qubit_ref)
  return
}

// -----

func.func @measure_bit_type() {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  // expected-error @+1 {{'qref.measure' op result #0 must be 1-bit signless integer, but got 'i8'}}
  %bit = qref.measure z %q : !qcc.qubit_ref -> i8
  return
}
