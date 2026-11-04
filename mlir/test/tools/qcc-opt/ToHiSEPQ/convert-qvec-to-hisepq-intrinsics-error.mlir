// RUN: qcc-opt %s -convert-qvec-to-hisepq-intrinsics="min-vlen=64 num-qubit-control-lines=128" --split-input-file \
// RUN:   --verify-diagnostics

// Validate pass options.
// RUN: echo 'module {}' | not qcc-opt -convert-qvec-to-hisepq-intrinsics=min-vlen=100 2>&1 \
// RUN:   | FileCheck %s --check-prefix=CHECK-BAD-VLEN
// RUN: echo 'module {}' | not qcc-opt -convert-qvec-to-hisepq-intrinsics=min-vlen=32 2>&1 \
// RUN:   | FileCheck %s --check-prefix=CHECK-SMALL-VLEN
// RUN: echo 'module {}' | not qcc-opt -convert-qvec-to-hisepq-intrinsics=num-qubit-control-lines=65537 2>&1 \
// RUN:   | FileCheck %s --check-prefix=CHECK-CONTROL-LINES
// RUN: echo 'module {}' | not qcc-opt -convert-qvec-to-hisepq-intrinsics=num-qubit-control-lines=0 2>&1 \
// RUN:   | FileCheck %s --check-prefix=CHECK-NO-CONTROL-LINES

// CHECK-BAD-VLEN:   'min-vlen' expects a power of two of at least 64, got 100
// CHECK-SMALL-VLEN: 'min-vlen' expects a power of two of at least 64, got 32
// CHECK-CONTROL-LINES: 'num-qubit-control-lines' expects 1 to 65536, got 65537
// CHECK-NO-CONTROL-LINES: 'num-qubit-control-lines' expects 1 to 65536, got 0

func.func @unsupported_single_gate() {
  %q0 = qcc.static [0] : !qcc.qubit
  %qs = vector.from_elements %q0 : vector<1x!qcc.qubit>
  // expected-error @+1 {{'qvec.single' op gate 'y' has no HiSEP-Q intrinsic}}
  %y = qvec.single y %qs : vector<1x!qcc.qubit>
  func.return
}

// -----

func.func @unsupported_pair_gate() {
  %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
  %ctrls = vector.from_elements %q0 : vector<1x!qcc.qubit>
  %tgts = vector.from_elements %q1 : vector<1x!qcc.qubit>
  // expected-error @+1 {{'qvec.pair' op gate 'iswap' has no HiSEP-Q intrinsic}}
  %ctrls_out, %tgts_out = qvec.pair iswap %ctrls, %tgts : vector<1x!qcc.qubit>
  func.return
}

// -----

func.func @measure_x() {
  %q0 = qcc.static [0] : !qcc.qubit
  %qs = vector.from_elements %q0 : vector<1x!qcc.qubit>
  // expected-error @+1 {{'qvec.measure' op basis 'x' has no HiSEP-Q intrinsic}}
  %qs_out, %result = qvec.measure x %qs : vector<1x!qcc.qubit> -> vector<1xi1>
  func.return
}

// -----

func.func @reset_x() {
  %q0 = qcc.static [0] : !qcc.qubit
  %qs = vector.from_elements %q0 : vector<1x!qcc.qubit>
  // expected-error @+1 {{'qvec.reset' op basis 'x' has no HiSEP-Q lowering}}
  %qs_out = qvec.reset x %qs : vector<1x!qcc.qubit>
  func.return
}

// -----

// The target qubit of the CX gate is chosen dynamically, we cannot handle this situation at the moment.

func.func @pair_target_chosen_at_runtime(%pick: i1) {
  %q0, %q1, %q2 = qcc.static [0, 1, 2] : !qcc.qubit
  %t = scf.if %pick -> (!qcc.qubit) {
    scf.yield %q1 : !qcc.qubit
  } else {
    scf.yield %q2 : !qcc.qubit
  }
  %ctrls = vector.from_elements %q0 : vector<1x!qcc.qubit>
  %tgts = vector.from_elements %t : vector<1x!qcc.qubit>
  // expected-error @+1 {{'qvec.pair' op expects every qubit vector element to trace back to a 'qcc.static' operation}}
  %ctrls_out, %tgts_out = qvec.pair cx %ctrls, %tgts : vector<1x!qcc.qubit>
  func.return
}

// -----

// TODO: So far no support for dynamic qubits. This and the next test case might work in the future.

func.func @qubit_vector_is_not_from_elements(%qs: vector<1x!qcc.qubit>) {
  // expected-error @+1 {{'qvec.single' op expects every qubit vector element to trace back to a 'qcc.static' operation}}
  %h = qvec.single h %qs : vector<1x!qcc.qubit>
  func.return
}

// -----

// A `vector.from_elements` is not enough on its own; every element has to come from a `qcc.static`.

func.func @qubit_vector_is_not_static(%q: !qcc.qubit) {
  %qs = vector.from_elements %q : vector<1x!qcc.qubit>
  // expected-error @+1 {{'qvec.measure' op expects every qubit vector element to trace back to a 'qcc.static' operation}}
  %qs_out, %result = qvec.measure z %qs : vector<1x!qcc.qubit> -> vector<1xi1>
  func.return
}

// -----


func.func @qubit_index_out_of_range() {
  %q0 = qcc.static [128] : !qcc.qubit
  %qs = vector.from_elements %q0 : vector<1x!qcc.qubit>
  // expected-error @+1 {{'qvec.single' op qubit index 128 exceeds the maximum of 127 for 128 qubit control lines}}
  %h = qvec.single h %qs : vector<1x!qcc.qubit>
  func.return
}

// -----

func.func @too_many_qubits() {
  %q0, %q1, %q2, %q3, %q4, %q5, %q6, %q7, %q8, %q9, %q10, %q11, %q12, %q13, %q14, %q15, %q16, %q17, %q18, %q19, %q20, %q21, %q22, %q23, %q24, %q25, %q26, %q27, %q28, %q29, %q30, %q31, %q32, %q33, %q34, %q35, %q36, %q37, %q38, %q39, %q40, %q41, %q42, %q43, %q44, %q45, %q46, %q47, %q48, %q49, %q50, %q51, %q52, %q53, %q54, %q55, %q56, %q57, %q58, %q59, %q60, %q61, %q62, %q63, %q64 = qcc.static [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64] : !qcc.qubit
  %qs = vector.from_elements
      %q0, %q1, %q2, %q3, %q4, %q5, %q6, %q7, %q8, %q9, %q10, %q11, %q12, %q13, %q14, %q15, %q16,
      %q17, %q18, %q19, %q20, %q21, %q22, %q23, %q24, %q25, %q26, %q27, %q28, %q29, %q30, %q31, %q32,
      %q33, %q34, %q35, %q36, %q37, %q38, %q39, %q40, %q41, %q42, %q43, %q44, %q45, %q46, %q47, %q48,
      %q49, %q50, %q51, %q52, %q53, %q54, %q55, %q56, %q57, %q58, %q59, %q60, %q61, %q62, %q63, %q64
      : vector<65x!qcc.qubit>
  // expected-error @+1 {{'qvec.single' op has 65 qubits, but at a minimum VLEN of 64 and a qubit element width of 8 the QV instructions address at most 64}}
  %h = qvec.single h %qs : vector<65x!qcc.qubit>
  func.return
}
