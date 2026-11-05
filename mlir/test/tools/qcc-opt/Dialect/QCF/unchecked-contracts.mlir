// RUN: qcc-opt %s --split-input-file -o /dev/null

// Invalid IR that no check rejects, neither the verifier nor a check pass. Move a case to the tests of the check that
// starts rejecting it. The RUN line catches this for the verifier only: when adding a check pass, go through this file.

// The bound qubits come back swapped. Yielding `%e0, %e1` would be valid and looks the same to the verifier.
func.func @yield_swapped_through_vector(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %r0, %r1 = qcf.if %cond (%a = %q0, %b = %q1) -> (!qcc.qubit, !qcc.qubit) {
    %v = vector.from_elements %a, %b : vector<2x!qcc.qubit>
    %e0 = vector.extract %v[0] : !qcc.qubit from vector<2x!qcc.qubit>
    %e1 = vector.extract %v[1] : !qcc.qubit from vector<2x!qcc.qubit>
    qcf.yield %e1, %e0 : !qcc.qubit, !qcc.qubit
  }
  return
}

// -----

// The result vector has its qubits (physically) swapped. Only the unswapped order is allowed.
func.func @vector_elements_swapped(%cond: i1) {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  %v_out = qcf.if %cond (%vb = %v) -> vector<2x!qcc.qubit> {
    %e0 = vector.extract %vb[0] : !qcc.qubit from vector<2x!qcc.qubit>
    %e1 = vector.extract %vb[1] : !qcc.qubit from vector<2x!qcc.qubit>
    %w = vector.from_elements %e1, %e0 : vector<2x!qcc.qubit>
    qcf.yield %w : vector<2x!qcc.qubit>
  }
  return
}

// -----

// An element of the vector binding and the scalar binding trade places. Valid would be if the scalar remains in the
// scalar lane and the vector in the vector lane (and not elementwise permuted).
func.func @element_traded_for_scalar_binding(%cond: i1) {
  %q0, %q1, %q2 = qcc.static [0, 1, 2] : !qcc.qubit
  %v = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
  %v_out, %s_out = qcf.if %cond (%vb = %v, %s = %q2) -> (vector<2x!qcc.qubit>, !qcc.qubit) {
    %e0 = vector.extract %vb[0] : !qcc.qubit from vector<2x!qcc.qubit>
    %e1 = vector.extract %vb[1] : !qcc.qubit from vector<2x!qcc.qubit>
    %w = vector.from_elements %e0, %s : vector<2x!qcc.qubit>
    qcf.yield %w, %e1 : vector<2x!qcc.qubit>, !qcc.qubit
  }
  return
}
