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
