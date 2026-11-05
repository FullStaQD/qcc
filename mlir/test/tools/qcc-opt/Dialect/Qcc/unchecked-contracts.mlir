// RUN: qcc-opt %s --split-input-file -o /dev/null

// Invalid IR that no check rejects, neither the verifier nor a check pass. Move a case to the tests of the check that
// starts rejecting it. The RUN line catches this for the verifier only: when adding a check pass, go through this file.

// Qubit 0 is taken out of the vector twice and consumed twice. Allowed is at most one usage.
func.func @extract_twice() {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  %e0 = vector.extract %v[0] : !qcc.qubit from vector<2x!qcc.qubit>
  %e1 = vector.extract %v[0] : !qcc.qubit from vector<2x!qcc.qubit>
  %a = qcirc.single h %e0 : !qcc.qubit
  %b = qcirc.single x %e1 : !qcc.qubit
  return
}

// -----

// Qubit 0 is taken out and put back at position 1, so the new vector holds qubit 0 twice. Allowed would be
// putting it back at position 0.
func.func @insert_elsewhere() {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  %e = vector.extract %v[0] : !qcc.qubit from vector<2x!qcc.qubit>
  %h = qcirc.single h %e : !qcc.qubit
  %w = vector.insert %h, %v[1] : !qcc.qubit into vector<2x!qcc.qubit>
  return
}

// -----

// The vector holds qubit 0 twice. The qubits of a vector must be distinct.
func.func @duplicate_qubits() {
  %q = qcc.static [0] : !qcc.qubit
  %w = vector.broadcast %q : !qcc.qubit to vector<2x!qcc.qubit>
  return
}

// -----

// The qubit is freed twice. Each qubit may be freed at most once.
func.func @dealloc_twice() {
  %q = qcc.alloc : !qcc.qubit_ref
  qcc.dealloc %q : !qcc.qubit_ref
  qcc.dealloc %q : !qcc.qubit_ref
  return
}

// -----

// Element 0 is freed on its own and again with the array.
func.func @dealloc_element_and_array() {
  %r = qcc.alloc : tensor<2x!qcc.qubit_ref>
  %c0 = arith.constant 0 : index
  %q = tensor.extract %r[%c0] : tensor<2x!qcc.qubit_ref>
  qcc.dealloc %q : !qcc.qubit_ref
  qcc.dealloc %r : tensor<2x!qcc.qubit_ref>
  return
}

// -----

// The array holds static qubits, which are never freed. Only a static qubit given directly is rejected.
func.func @dealloc_static_qubits_of_array() {
  %q0, %q1 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  %r = tensor.from_elements %q0, %q1 : tensor<2x!qcc.qubit_ref>
  qcc.dealloc %r : tensor<2x!qcc.qubit_ref>
  return
}

// -----

// The qubit is acted on after it is freed.
func.func @use_after_dealloc() {
  %q = qcc.alloc : !qcc.qubit_ref
  qcc.dealloc %q : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  return
}
