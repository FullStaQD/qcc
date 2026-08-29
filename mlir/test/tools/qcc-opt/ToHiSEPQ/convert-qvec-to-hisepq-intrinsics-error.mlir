// RUN: qcc-opt %s -convert-qvec-to-hisepq-intrinsics=min-vlen=64 --split-input-file --verify-diagnostics

// Validate pass options.
// RUN: echo 'module {}' | not qcc-opt -convert-qvec-to-hisepq-intrinsics=min-vlen=100 2>&1 \
// RUN:   | FileCheck %s --check-prefix=CHECK-BAD-VLEN
// RUN: echo 'module {}' | not qcc-opt -convert-qvec-to-hisepq-intrinsics=min-vlen=32 2>&1 \
// RUN:   | FileCheck %s --check-prefix=CHECK-SMALL-VLEN
// RUN: echo 'module {}' | not qcc-opt -convert-qvec-to-hisepq-intrinsics=qubit-element-width=32 2>&1 \
// RUN:   | FileCheck %s --check-prefix=CHECK-QEW

// CHECK-BAD-VLEN:   'min-vlen' expects a power of two of at least 64, got 100
// CHECK-SMALL-VLEN: 'min-vlen' expects a power of two of at least 64, got 32
// CHECK-QEW:    'qubit-element-width' expects 8 or 16, got 32

func.func @unsupported_single_gate() {
  %q0 = qco.static 0 : !qco.qubit
  %qs = vector.from_elements %q0 : vector<1x!qco.qubit>
  // expected-error @+1 {{'qvec.single' op gate 'y' has no HiSEP-Q intrinsic}}
  %y = qvec.single y %qs : vector<1x!qco.qubit>
  func.return
}

// -----

func.func @unsupported_pair_gate() {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %ctrls = vector.from_elements %q0 : vector<1x!qco.qubit>
  %tgts = vector.from_elements %q1 : vector<1x!qco.qubit>
  // expected-error @+1 {{'qvec.pair' op gate 'iswap' has no HiSEP-Q intrinsic}}
  %ctrls_out, %tgts_out = qvec.pair iswap %ctrls, %tgts : vector<1x!qco.qubit>
  func.return
}

// -----

// Both operands of a pair are checked before either is materialized, so a bad target is reported
// once and nothing is left behind for the controls.

func.func @pair_target_is_not_static(%t: !qco.qubit) {
  %q0 = qco.static 0 : !qco.qubit
  %ctrls = vector.from_elements %q0 : vector<1x!qco.qubit>
  %tgts = vector.from_elements %t : vector<1x!qco.qubit>
  // expected-error @+1 {{'qvec.pair' op expects every qubit vector element to trace back to a 'qco.static' operation}}
  %ctrls_out, %tgts_out = qvec.pair cx %ctrls, %tgts : vector<1x!qco.qubit>
  func.return
}

// -----

// TODO: So far no support for dynamic qubits. This and the next test case might work in the future.

func.func @qubit_vector_is_not_from_elements(%qs: vector<1x!qco.qubit>) {
  // expected-error @+1 {{'qvec.single' op expects every qubit vector element to trace back to a 'qco.static' operation}}
  %h = qvec.single h %qs : vector<1x!qco.qubit>
  func.return
}

// -----

// A `vector.from_elements` is not enough on its own; every element has to be a `qco.static`.

func.func @qubit_vector_is_not_static(%q: !qco.qubit) {
  %qs = vector.from_elements %q : vector<1x!qco.qubit>
  // expected-error @+1 {{'qvec.mz' op expects every qubit vector element to trace back to a 'qco.static' operation}}
  %qs_out, %result = qvec.mz %qs : vector<1x!qco.qubit> -> vector<1xi1>
  func.return
}

// -----

// Qubit indices travel as i8, so each one has to fit in one.

func.func @qubit_index_out_of_range() {
  %q0 = qco.static 256 : !qco.qubit
  %qs = vector.from_elements %q0 : vector<1x!qco.qubit>
  // expected-error @+1 {{'qvec.single' op qubit index 256 does not fit in i8}}
  %h = qvec.single h %qs : vector<1x!qco.qubit>
  func.return
}

// -----

func.func @too_many_qubits() {
  %q0 = qco.static 0 : !qco.qubit
  %q1 = qco.static 1 : !qco.qubit
  %q2 = qco.static 2 : !qco.qubit
  %q3 = qco.static 3 : !qco.qubit
  %q4 = qco.static 4 : !qco.qubit
  %q5 = qco.static 5 : !qco.qubit
  %q6 = qco.static 6 : !qco.qubit
  %q7 = qco.static 7 : !qco.qubit
  %q8 = qco.static 8 : !qco.qubit
  %q9 = qco.static 9 : !qco.qubit
  %q10 = qco.static 10 : !qco.qubit
  %q11 = qco.static 11 : !qco.qubit
  %q12 = qco.static 12 : !qco.qubit
  %q13 = qco.static 13 : !qco.qubit
  %q14 = qco.static 14 : !qco.qubit
  %q15 = qco.static 15 : !qco.qubit
  %q16 = qco.static 16 : !qco.qubit
  %q17 = qco.static 17 : !qco.qubit
  %q18 = qco.static 18 : !qco.qubit
  %q19 = qco.static 19 : !qco.qubit
  %q20 = qco.static 20 : !qco.qubit
  %q21 = qco.static 21 : !qco.qubit
  %q22 = qco.static 22 : !qco.qubit
  %q23 = qco.static 23 : !qco.qubit
  %q24 = qco.static 24 : !qco.qubit
  %q25 = qco.static 25 : !qco.qubit
  %q26 = qco.static 26 : !qco.qubit
  %q27 = qco.static 27 : !qco.qubit
  %q28 = qco.static 28 : !qco.qubit
  %q29 = qco.static 29 : !qco.qubit
  %q30 = qco.static 30 : !qco.qubit
  %q31 = qco.static 31 : !qco.qubit
  %q32 = qco.static 32 : !qco.qubit
  %q33 = qco.static 33 : !qco.qubit
  %q34 = qco.static 34 : !qco.qubit
  %q35 = qco.static 35 : !qco.qubit
  %q36 = qco.static 36 : !qco.qubit
  %q37 = qco.static 37 : !qco.qubit
  %q38 = qco.static 38 : !qco.qubit
  %q39 = qco.static 39 : !qco.qubit
  %q40 = qco.static 40 : !qco.qubit
  %q41 = qco.static 41 : !qco.qubit
  %q42 = qco.static 42 : !qco.qubit
  %q43 = qco.static 43 : !qco.qubit
  %q44 = qco.static 44 : !qco.qubit
  %q45 = qco.static 45 : !qco.qubit
  %q46 = qco.static 46 : !qco.qubit
  %q47 = qco.static 47 : !qco.qubit
  %q48 = qco.static 48 : !qco.qubit
  %q49 = qco.static 49 : !qco.qubit
  %q50 = qco.static 50 : !qco.qubit
  %q51 = qco.static 51 : !qco.qubit
  %q52 = qco.static 52 : !qco.qubit
  %q53 = qco.static 53 : !qco.qubit
  %q54 = qco.static 54 : !qco.qubit
  %q55 = qco.static 55 : !qco.qubit
  %q56 = qco.static 56 : !qco.qubit
  %q57 = qco.static 57 : !qco.qubit
  %q58 = qco.static 58 : !qco.qubit
  %q59 = qco.static 59 : !qco.qubit
  %q60 = qco.static 60 : !qco.qubit
  %q61 = qco.static 61 : !qco.qubit
  %q62 = qco.static 62 : !qco.qubit
  %q63 = qco.static 63 : !qco.qubit
  %q64 = qco.static 64 : !qco.qubit
  %qs = vector.from_elements
      %q0, %q1, %q2, %q3, %q4, %q5, %q6, %q7, %q8, %q9, %q10, %q11, %q12, %q13, %q14, %q15, %q16,
      %q17, %q18, %q19, %q20, %q21, %q22, %q23, %q24, %q25, %q26, %q27, %q28, %q29, %q30, %q31, %q32,
      %q33, %q34, %q35, %q36, %q37, %q38, %q39, %q40, %q41, %q42, %q43, %q44, %q45, %q46, %q47, %q48,
      %q49, %q50, %q51, %q52, %q53, %q54, %q55, %q56, %q57, %q58, %q59, %q60, %q61, %q62, %q63, %q64
      : vector<65x!qco.qubit>
  // expected-error @+1 {{'qvec.single' op has 65 qubits, but at a minimum VLEN of 64 and a qubit element width of 8 the QV instructions address at most 64}}
  %h = qvec.single h %qs : vector<65x!qco.qubit>
  func.return
}
