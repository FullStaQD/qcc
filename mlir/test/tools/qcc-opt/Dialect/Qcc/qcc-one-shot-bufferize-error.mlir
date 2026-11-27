// RUN: qcc-opt %s --qcc-one-shot-bufferize --split-input-file --verify-diagnostics

// The array changes per iteration, so the loop must be unrolled first.
func.func @loop(%n: index) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %a = qcc.alloc : tensor<2x!qcc.qubit_ref>
  %b = qcc.alloc : tensor<2x!qcc.qubit_ref>
  // expected-error @+1 {{'scf.for' op holds an array of qubits, but qcc-one-shot-bufferize expects only 'qcc.alloc', 'qcc.dealloc' and 'tensor' ops to hold arrays of qubits}}
  %r:2 = scf.for %i = %c0 to %n step %c1 iter_args(%x = %a, %y = %b)
      -> (tensor<2x!qcc.qubit_ref>, tensor<2x!qcc.qubit_ref>) {
    %q = tensor.extract %x[%c0] : tensor<2x!qcc.qubit_ref>
    qref.single h %q : !qcc.qubit_ref
    scf.yield %y, %x : tensor<2x!qcc.qubit_ref>, tensor<2x!qcc.qubit_ref>
  }
  return
}

// -----

// expected-error @+1 {{'func.func' op holds an array of qubits, but qcc-one-shot-bufferize expects only 'qcc.alloc', 'qcc.dealloc' and 'tensor' ops to hold arrays of qubits}}
func.func @argument(%r: tensor<2x!qcc.qubit_ref>) {
  return
}
