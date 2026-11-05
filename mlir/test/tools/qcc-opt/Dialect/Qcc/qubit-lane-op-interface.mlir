// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// The verifier of the `QubitLaneOpInterface`, on `qcf.if`. Only the generic form can express these errors.

func.func @qubit_after_classical_result(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcf.if' op qubit result #2 follows a non-qubit result: the qubit results must be the leading results}}
  %r:3 = "qcf.if"(%q, %cond) ({
  ^bb0(%a: !qcc.qubit):
    "qcf.yield"(%a) : (!qcc.qubit) -> ()
  }, {
  }) : (!qcc.qubit, i1) -> (!qcc.qubit, i1, !qcc.qubit)
  return
}

// -----

func.func @lane_without_result(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcf.if' op has 1 qubit operand(s) but 0 qubit result(s): every qubit lane has both ends}}
  %r = "qcf.if"(%q, %cond) ({
  ^bb0(%a: !qcc.qubit):
    "qcf.yield"(%cond) : (i1) -> ()
  }, {
  }) : (!qcc.qubit, i1) -> (i1)
  return
}

// -----

func.func @lane_changes_type(%cond: i1) {
  %q = qcc.static [0] : !qcc.qubit
  // expected-error @+1 {{'qcf.if' op qubit lane #0 enters as '!qcc.qubit' but leaves as 'vector<1x!qcc.qubit>'}}
  %r = "qcf.if"(%q, %cond) ({
  ^bb0(%a: !qcc.qubit):
    %v = vector.from_elements %a : vector<1x!qcc.qubit>
    "qcf.yield"(%v) : (vector<1x!qcc.qubit>) -> ()
  }, {
  }) : (!qcc.qubit, i1) -> (vector<1x!qcc.qubit>)
  return
}
