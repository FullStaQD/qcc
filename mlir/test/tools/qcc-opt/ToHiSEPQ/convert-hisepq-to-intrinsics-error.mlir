// RUN: qcc-opt %s -convert-hisepq-to-intrinsics --split-input-file --verify-diagnostics

func.func @unsupported_single_gate() {
  %q0 = qc.static 0 : !qc.qubit
  %qs = vector.from_elements %q0 : vector<1x!qc.qubit>
  // expected-error @+1 {{'hisepq.single' op gate 'y' has no HiSEP-Q intrinsic}}
  hisepq.single y %qs : vector<1x!qc.qubit>
  func.return
}

// -----

func.func @unsupported_pair_gate() {
  %q0 = qc.static 0 : !qc.qubit
  %q1 = qc.static 1 : !qc.qubit
  %ctrls = vector.from_elements %q0 : vector<1x!qc.qubit>
  %tgts = vector.from_elements %q1 : vector<1x!qc.qubit>
  // expected-error @+1 {{'hisepq.pair' op gate 'iswap' has no HiSEP-Q intrinsic}}
  hisepq.pair iswap %ctrls, %tgts : vector<1x!qc.qubit>
  func.return
}

// -----

// TODO: So far no support for dynamic qubits. This and the next test case might work in the future.

func.func @qubit_vector_is_not_from_elements(%qs: vector<1x!qc.qubit>) {
  // expected-error @+1 {{'hisepq.single' op expects every qubit vector to be a 'vector.from_elements' of 'qc.static' operations}}
  hisepq.single h %qs : vector<1x!qc.qubit>
  func.return
}

// -----

// A `vector.from_elements` is not enough on its own; every lane has to be a `qc.static`.

func.func @qubit_vector_is_not_static(%q: !qc.qubit) {
  %qs = vector.from_elements %q : vector<1x!qc.qubit>
  // expected-error @+1 {{'hisepq.mz' op expects every qubit vector to be a 'vector.from_elements' of 'qc.static' operations}}
  %result = hisepq.mz %qs : vector<1x!qc.qubit> -> vector<1xi1>
  func.return
}

// -----

// Lane values travel as i8, so the qubit index has to fit in one.

func.func @qubit_index_out_of_range() {
  %q0 = qc.static 256 : !qc.qubit
  %qs = vector.from_elements %q0 : vector<1x!qc.qubit>
  // expected-error @+1 {{'hisepq.single' op qubit index 256 does not fit in i8}}
  hisepq.single h %qs : vector<1x!qc.qubit>
  func.return
}

// -----

// LMUL 8 is the widest QV vector, i.e. 64 lanes.

func.func @too_many_lanes() {
  %q0 = qc.static 0 : !qc.qubit
  %q1 = qc.static 1 : !qc.qubit
  %q2 = qc.static 2 : !qc.qubit
  %q3 = qc.static 3 : !qc.qubit
  %q4 = qc.static 4 : !qc.qubit
  %q5 = qc.static 5 : !qc.qubit
  %q6 = qc.static 6 : !qc.qubit
  %q7 = qc.static 7 : !qc.qubit
  %q8 = qc.static 8 : !qc.qubit
  %q9 = qc.static 9 : !qc.qubit
  %q10 = qc.static 10 : !qc.qubit
  %q11 = qc.static 11 : !qc.qubit
  %q12 = qc.static 12 : !qc.qubit
  %q13 = qc.static 13 : !qc.qubit
  %q14 = qc.static 14 : !qc.qubit
  %q15 = qc.static 15 : !qc.qubit
  %q16 = qc.static 16 : !qc.qubit
  %q17 = qc.static 17 : !qc.qubit
  %q18 = qc.static 18 : !qc.qubit
  %q19 = qc.static 19 : !qc.qubit
  %q20 = qc.static 20 : !qc.qubit
  %q21 = qc.static 21 : !qc.qubit
  %q22 = qc.static 22 : !qc.qubit
  %q23 = qc.static 23 : !qc.qubit
  %q24 = qc.static 24 : !qc.qubit
  %q25 = qc.static 25 : !qc.qubit
  %q26 = qc.static 26 : !qc.qubit
  %q27 = qc.static 27 : !qc.qubit
  %q28 = qc.static 28 : !qc.qubit
  %q29 = qc.static 29 : !qc.qubit
  %q30 = qc.static 30 : !qc.qubit
  %q31 = qc.static 31 : !qc.qubit
  %q32 = qc.static 32 : !qc.qubit
  %q33 = qc.static 33 : !qc.qubit
  %q34 = qc.static 34 : !qc.qubit
  %q35 = qc.static 35 : !qc.qubit
  %q36 = qc.static 36 : !qc.qubit
  %q37 = qc.static 37 : !qc.qubit
  %q38 = qc.static 38 : !qc.qubit
  %q39 = qc.static 39 : !qc.qubit
  %q40 = qc.static 40 : !qc.qubit
  %q41 = qc.static 41 : !qc.qubit
  %q42 = qc.static 42 : !qc.qubit
  %q43 = qc.static 43 : !qc.qubit
  %q44 = qc.static 44 : !qc.qubit
  %q45 = qc.static 45 : !qc.qubit
  %q46 = qc.static 46 : !qc.qubit
  %q47 = qc.static 47 : !qc.qubit
  %q48 = qc.static 48 : !qc.qubit
  %q49 = qc.static 49 : !qc.qubit
  %q50 = qc.static 50 : !qc.qubit
  %q51 = qc.static 51 : !qc.qubit
  %q52 = qc.static 52 : !qc.qubit
  %q53 = qc.static 53 : !qc.qubit
  %q54 = qc.static 54 : !qc.qubit
  %q55 = qc.static 55 : !qc.qubit
  %q56 = qc.static 56 : !qc.qubit
  %q57 = qc.static 57 : !qc.qubit
  %q58 = qc.static 58 : !qc.qubit
  %q59 = qc.static 59 : !qc.qubit
  %q60 = qc.static 60 : !qc.qubit
  %q61 = qc.static 61 : !qc.qubit
  %q62 = qc.static 62 : !qc.qubit
  %q63 = qc.static 63 : !qc.qubit
  %q64 = qc.static 64 : !qc.qubit
  %qs = vector.from_elements
      %q0, %q1, %q2, %q3, %q4, %q5, %q6, %q7, %q8, %q9, %q10, %q11, %q12, %q13, %q14, %q15, %q16,
      %q17, %q18, %q19, %q20, %q21, %q22, %q23, %q24, %q25, %q26, %q27, %q28, %q29, %q30, %q31, %q32,
      %q33, %q34, %q35, %q36, %q37, %q38, %q39, %q40, %q41, %q42, %q43, %q44, %q45, %q46, %q47, %q48,
      %q49, %q50, %q51, %q52, %q53, %q54, %q55, %q56, %q57, %q58, %q59, %q60, %q61, %q62, %q63, %q64
      : vector<65x!qc.qubit>
  // expected-error @+1 {{'hisepq.single' op has 65 qubits, but the QV instructions address at most 64}}
  hisepq.single h %qs : vector<65x!qc.qubit>
  func.return
}
