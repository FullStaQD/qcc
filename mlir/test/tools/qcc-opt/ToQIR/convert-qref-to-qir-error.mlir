// RUN: qcc-opt %s -convert-qref-to-qir --split-input-file --verify-diagnostics

// A gate outside the supported native gate set has no QIR mapping.
func.func @unsupported_single() attributes { qcc.entry_point } {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  // expected-error @+1 {{'qref.single' op applies gate 'y', which convert-qref-to-qir does not support}}
  qref.single y %q : !qcc.qubit_ref
  return
}

// -----

func.func @unsupported_pair() attributes { qcc.entry_point } {
  %q0, %q1 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  // expected-error @+1 {{'qref.pair' op applies gate 'swap', which convert-qref-to-qir does not support}}
  qref.pair swap %q0, %q1 : !qcc.qubit_ref
  return
}

// -----

func.func @unsupported_measure() attributes { qcc.entry_point } {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  // expected-error @+1 {{'qref.measure' op measures in basis 'x', which convert-qref-to-qir does not support}}
  %bit = qref.measure x %q : !qcc.qubit_ref -> i1
  return
}

// -----

func.func @unsupported_reset() attributes { qcc.entry_point } {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  // expected-error @+1 {{'qref.reset' op resets in basis 'x', which convert-qref-to-qir does not support}}
  qref.reset x %q : !qcc.qubit_ref
  return
}

// -----

// Dynamic qubits are not supported (yet).
func.func @alloc() attributes { qcc.entry_point } {
  // expected-error @+1 {{'qcc.alloc' op is not supported by convert-qref-to-qir on qubit references}}
  %q = qcc.alloc : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  return
}

// -----

// expected-error @+1 {{'func.func' op has a qubit reference argument, which convert-qref-to-qir does not support}}
func.func @argument(%q: !qcc.qubit_ref) attributes { qcc.entry_point } {
  qref.single h %q : !qcc.qubit_ref
  return
}

// -----

func.func @no_entry_point() {
  // expected-error @+1 {{'qcc.static_ref' op uses qubit references outside an entry point, which convert-qref-to-qir does not support}}
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  return
}
