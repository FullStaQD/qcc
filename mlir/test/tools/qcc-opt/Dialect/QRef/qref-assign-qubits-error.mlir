// RUN: qcc-opt %s --qref-assign-qubits --split-input-file --verify-diagnostics

func.func @dynamic_size(%n: index) {
  // expected-error @+1 {{'qcc.alloc' op allocates a dynamic number of qubits, but qref-assign-qubits expects a constant number}}
  %r = qcc.alloc %n : tensor<?x!qcc.qubit_ref>
  return
}

// -----

func.func @negative_size() {
  %c-1 = arith.constant -1 : index
  // expected-error @+1 {{'qcc.alloc' op allocates a negative number of qubits: -1}}
  %r = qcc.alloc %c-1 : tensor<?x!qcc.qubit_ref>
  return
}

// -----

func.func @dealloc_element() {
  %c0 = arith.constant 0 : index
  %r = qcc.alloc : tensor<2x!qcc.qubit_ref>
  %q = tensor.extract %r[%c0] : tensor<2x!qcc.qubit_ref>
  // expected-error @+1 {{'qcc.dealloc' op frees qubits other than the result of a 'qcc.alloc', which qref-assign-qubits does not support}}
  qcc.dealloc %q : !qcc.qubit_ref
  return
}

// -----

func.func @loop_without_dealloc(%n: index) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  scf.for %i = %c0 to %n step %c1 {
    // expected-error @+1 {{'qcc.alloc' op may run repeatedly, but qref-assign-qubits expects such an allocation to be freed by a 'qcc.dealloc' in its block}}
    %q = qcc.alloc : !qcc.qubit_ref
    qref.single x %q : !qcc.qubit_ref
  }
  return
}

// -----

// A sequential loop inside a parallel one still runs in parallel with itself.
func.func @forall(%n: index) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  scf.forall (%i) in (%n) {
    scf.for %j = %c0 to %n step %c1 {
      // expected-error @+1 {{'qcc.alloc' op may run in parallel with itself in 'scf.forall', which qref-assign-qubits does not support}}
      %q = qcc.alloc : !qcc.qubit_ref
      qref.single x %q : !qcc.qubit_ref
      qcc.dealloc %q : !qcc.qubit_ref
    }
  }
  return
}

// -----

func.func @parallel(%n: index) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  scf.parallel (%i) = (%c0) to (%n) step (%c1) {
    // expected-error @+1 {{'qcc.alloc' op may run in parallel with itself in 'scf.parallel', which qref-assign-qubits does not support}}
    %q = qcc.alloc : !qcc.qubit_ref
    qref.single x %q : !qcc.qubit_ref
    qcc.dealloc %q : !qcc.qubit_ref
  }
  return
}
