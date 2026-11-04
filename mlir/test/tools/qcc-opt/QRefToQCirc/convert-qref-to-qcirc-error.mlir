// RUN: qcc-opt %s --convert-qref-to-qcirc --split-input-file --verify-diagnostics

// A callee may act on the qubits too.
func.func @call() {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  // expected-error @+1 {{'func.call' op calls a function, which convert-qref-to-qcirc does not support}}
  func.call @callee() : () -> ()
  return
}
func.func private @callee()

// -----

// expected-error @+1 {{'func.func' op has a qubit reference argument, which convert-qref-to-qcirc does not support}}
func.func @argument(%q: !qcc.qubit_ref) {
  qref.single h %q : !qcc.qubit_ref
  return
}

// -----

func.func @alloc() {
  // expected-error @+1 {{'qcc.alloc' op is not supported by convert-qref-to-qcirc}}
  %q = qcc.alloc : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  return
}

// -----

func.func @static() {
  // expected-error @+1 {{'qcc.static' op uses '!qcc.qubit' in a function that uses '!qcc.qubit_ref'; mixing qubit types is ill-defined}}
  %q = qcc.static [0] : !qcc.qubit
  %r = qcc.static_ref [0] : !qcc.qubit_ref
  // Ill-defined because MLIR is free to reorder the x and h gates below (side effects)
  %q1 = qcirc.single x %q : !qcc.qubit
  qref.single h %r : !qcc.qubit_ref
  return
}

// -----

func.func @array() {
  %q:2 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  // expected-error @+1 {{'tensor.from_elements' op is not supported by convert-qref-to-qcirc on qubit references}}
  %r = tensor.from_elements %q#0, %q#1 : tensor<2x!qcc.qubit_ref>
  return
}

// -----

func.func @returned() -> !qcc.qubit_ref {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  // expected-error @+1 {{'func.return' op is not supported by convert-qref-to-qcirc on qubit references}}
  return %q : !qcc.qubit_ref
}

// -----

func.func @yielded(%cond: i1) {
  %q:2 = qcc.static_ref [0, 1] : !qcc.qubit_ref
  // expected-error @+1 {{'scf.if' op is not supported by convert-qref-to-qcirc on qubit references}}
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
func.func @if_in_loop(%n: index, %cond: i1) {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  // expected-note @+1 {{see the enclosing op}}
  scf.for %i = %c0 to %n step %c1 {
    scf.if %cond {
      // expected-error @+1 {{'qref.single' op is inside 'scf.for', which convert-qref-to-qcirc does not support}}
      qref.single h %q : !qcc.qubit_ref
    }
  }
  return
}

// -----

// qref allows multiple blocks but qcirc doesn't. Unstructured control flow has to be raised to structured control flow
// before using this pass.
// expected-error @+1 {{'func.func' op has multiple blocks, which convert-qref-to-qcirc does not support}}
func.func @blocks(%cond: i1) {
  %q = qcc.static_ref [0] : !qcc.qubit_ref
  cf.cond_br %cond, ^bb1, ^bb2
^bb1:
  qref.single h %q : !qcc.qubit_ref
  cf.br ^bb2
^bb2:
  return
}
