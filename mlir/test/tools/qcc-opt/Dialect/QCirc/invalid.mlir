// RUN: qcc-opt %s --split-input-file --verify-diagnostics

func.func @missing_parameter() {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcirc.single' op gate 'rz' takes 1 parameter(s), got 0}}
  %rz = qcirc.single rz %q : !qcc.qubit
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

func.func @measure_bit_type() {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcirc.measure' op result #1 must be 1-bit signless integer, but got 'i8'}}
  %m, %bit = qcirc.measure z %q : !qcc.qubit -> i8
  return
}
