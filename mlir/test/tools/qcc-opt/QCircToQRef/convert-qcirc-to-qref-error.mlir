// RUN: qcc-opt %s --convert-qcirc-to-qref --split-input-file --verify-diagnostics

func.func @vector() {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'vector.from_elements' op uses a vector of qubits, which convert-qcirc-to-qref does not support}}
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  return
}

// -----

func.func @scf_if(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  // expected-error @+1 {{'scf.if' op is not supported by convert-qcirc-to-qref on qubits}}
  %q = scf.if %cond -> !qcc.qubit {
    scf.yield %q0 : !qcc.qubit
  } else {
    scf.yield %q1 : !qcc.qubit
  }
  return
}

// -----

// A `qref` op (has effects) has no defined order relative to the `qcirc` ops (no memory effects) on the same qubit.
func.func @static_ref() {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcc.static_ref' op uses '!qcc.qubit_ref' in a function that uses '!qcc.qubit'; mixing qubit types is ill-defined}}
  %r = qcc.static_ref [0] : !qcc.qubit_ref
  // Order of h and x not well-defined (h gate could be sunk after x gate), hence mixing qubit types must be rejected.
  %q1 = qcirc.single h %q : !qcc.qubit
  qref.single x %r : !qcc.qubit_ref
  return
}

// -----

func.func @qubit_ref_argument(%r: !qcc.qubit_ref) {
  %q = qcc.static [0] : !qcc.qubit
  %q1 = qcirc.single h %q : !qcc.qubit
  // expected-error @+1 {{'qref.single' op uses '!qcc.qubit_ref' in a function that uses '!qcc.qubit'; mixing qubit types is ill-defined}}
  qref.single x %r : !qcc.qubit_ref
  return
}
