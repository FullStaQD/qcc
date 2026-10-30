// RUN: qcc-opt %s --convert-qref-to-qcirc --split-input-file --verify-diagnostics

// A callee may act on the qubits too.
func.func @call() {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  // expected-error @+1 {{'func.call' op is not supported: a function acting on qubits must be self-contained}}
  func.call @callee() : () -> ()
  return
}
func.func private @callee()

// -----

// expected-error @+1 {{'func.func' op has a qubit reference argument, but every qubit must come from 'qcc.static_ref'}}
func.func @argument(%q: !qcc.qubit_ref) {
  qref.single h %q : !qcc.qubit_ref
  return
}

// -----

func.func @alloc() {
  // expected-error @+1 {{'qcc.alloc' op is not supported on qubit references: every qubit must come from 'qcc.static_ref', and only gates, measurements and resets may use it}}
  %q = qcc.alloc : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  return
}

// -----

func.func @array() {
  %q:2 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  // expected-error @+1 {{'tensor.from_elements' op is not supported on qubit references}}
  %r = tensor.from_elements %q#0, %q#1 : tensor<2x!qcc.qubit_ref>
  %c0 = arith.constant 0 : index
  %e = tensor.extract %r[%c0] : tensor<2x!qcc.qubit_ref>
  qref.single h %e : !qcc.qubit_ref
  return
}

// -----

func.func @returned() -> !qcc.qubit_ref {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  // expected-error @+1 {{'func.return' op is not supported on qubit references}}
  return %q : !qcc.qubit_ref
}

// -----

func.func @yielded(%cond: i1) {
  %q:2 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  // expected-error @+1 {{'scf.if' op is not supported on qubit references}}
  %r = scf.if %cond -> !qcc.qubit_ref {
    scf.yield %q#0 : !qcc.qubit_ref
  } else {
    scf.yield %q#1 : !qcc.qubit_ref
  }
  qref.single h %r : !qcc.qubit_ref
  return
}

// -----

// Loops are not supported yet.
func.func @loop(%n: index) {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  // expected-note @+1 {{see the enclosing op}}
  scf.for %i = %c0 to %n step %c1 {
    // expected-error @+1 {{'qref.single' op must sit at the top level of the function or inside 'scf.if', but is inside 'scf.for'}}
    qref.single h %q : !qcc.qubit_ref
  }
  return
}

// -----

func.func @if_in_loop(%n: index, %cond: i1) {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  // expected-note @+1 {{see the enclosing op}}
  scf.for %i = %c0 to %n step %c1 {
    scf.if %cond {
      // expected-error @+1 {{'qref.single' op must sit at the top level of the function or inside 'scf.if', but is inside 'scf.for'}}
      qref.single h %q : !qcc.qubit_ref
    }
  }
  return
}

// -----

// Unstructured control flow is not supported yet.
// expected-error @+1 {{'func.func' op acts on qubits, so it must have a single block: only 'scf.if' is supported as control flow around qubit ops}}
func.func @blocks(%cond: i1) {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  cf.cond_br %cond, ^bb1, ^bb2
^bb1:
  qref.single h %q : !qcc.qubit_ref
  cf.br ^bb2
^bb2:
  return
}
