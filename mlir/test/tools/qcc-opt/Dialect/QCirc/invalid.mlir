// RUN: qcc-opt %s --split-input-file --verify-diagnostics

func.func @missing_parameter() {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcirc.single' op gate 'rz' takes 1 parameter(s), got 0}}
  %rz = qcirc.single rz %q : !qcc.qubit
  return
}

// -----

// There is no identity gate. Decompose into e.g. rz(0) instead.
func.func @identity() {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error-re @+2 {{expected one of [{{.*}}] for single-qubit gate kind, got: i}}
  // expected-error @+1 {{failed to parse QCirc_SingleGateKindAttr parameter 'value'}}
  %i = qcirc.single i %q : !qcc.qubit
  return
}

// -----

func.func @parameter_type(%theta: f32) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcirc.single' op operand #1 must be variadic of 64-bit float angle, but got 'f32'}}
  %rz = qcirc.single rz(%theta) %q : !qcc.qubit, f32
  return
}

// -----

func.func @qubit_type(%q: i1) {
  // expected-error @+1 {{'qcirc.single' op operand #0 must be qubit value, but got 'i1'}}
  %h = qcirc.single h %q : i1
  return
}

// -----

func.func @pair_too_many_parameters(%theta: f64) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'qcirc.pair' op gate 'cx' takes 0 parameter(s), got 1}}
  %a, %b = qcirc.pair cx(%theta) %q0, %q1 : !qcc.qubit, f64
  return
}

// -----

func.func @global_matrix_size(%angles: tensor<3x3xf64>) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'qcirc.global' op angle matrix 'tensor<3x3xf64>' must be 2x2 to match the number of qubits}}
  %a, %b = qcirc.global zz(%angles) %q0, %q1 : !qcc.qubit, tensor<3x3xf64>
  return
}

// -----

// Only a static shape can be checked against the number of qubits.
func.func @global_matrix_dynamic(%angles: tensor<?x?xf64>) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'qcirc.global' op operand #2 must be statically shaped 2D tensor of 64-bit float values, but got 'tensor<?x?xf64>'}}
  %a, %b = qcirc.global zz(%angles) %q0, %q1 : !qcc.qubit, tensor<?x?xf64>
  return
}

// -----

func.func @global_matrix_asymmetric() {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %angles = arith.constant dense<[[0.0, 1.0], [2.0, 0.0]]> : tensor<2x2xf64>
  // expected-error @+1 {{'qcirc.global' op angle matrix must be symmetric, entries (1, 0) and (0, 1) differ}}
  %a, %b = qcirc.global zz(%angles) %q0, %q1 : !qcc.qubit, tensor<2x2xf64>
  return
}

// -----

func.func @global_matrix_diagonal() {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %angles = arith.constant dense<[[0.0, 1.0], [1.0, 3.0]]> : tensor<2x2xf64>
  // expected-error @+1 {{'qcirc.global' op angle matrix must have a zero diagonal, entry (1, 1) is 3.000000e+00}}
  %a, %b = qcirc.global zz(%angles) %q0, %q1 : !qcc.qubit, tensor<2x2xf64>
  return
}

// -----

// Checked by the `QubitLaneOpInterface`: the custom assembly cannot spell this.
func.func @global_lane_without_result(%angles: tensor<2x2xf64>) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'qcirc.global' op has 2 qubit operand(s) but 1 qubit result(s): every qubit lane has both ends}}
  %a = "qcirc.global"(%q0, %q1, %angles) {gate_kind = #qcirc<global_gate zz>} : (!qcc.qubit, !qcc.qubit, tensor<2x2xf64>) -> (!qcc.qubit)
  return
}

// -----

func.func @measure_bit_type() {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcirc.measure' op result #1 must be 1-bit signless integer, but got 'i8'}}
  %m, %bit = qcirc.measure z %q : !qcc.qubit -> i8
  return
}
