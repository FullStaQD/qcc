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
