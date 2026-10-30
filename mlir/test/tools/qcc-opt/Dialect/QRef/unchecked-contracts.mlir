// RUN: qcc-opt %s --split-input-file -o /dev/null

// Invalid IR that no check rejects, neither the verifier nor a check pass. Move a case to the tests of the check that
// starts rejecting it. The RUN line catches this for the verifier only: when adding a check pass, go through this file.

// Both references name element 0 of the array. A pair acts on distinct qubits.
func.func @pair_same_element() {
  %r = qcc.alloc : tensor<2x!qcc.qubit_ref>
  %c0 = arith.constant 0 : index
  %a = tensor.extract %r[%c0] : tensor<2x!qcc.qubit_ref>
  %b = tensor.extract %r[%c0] : tensor<2x!qcc.qubit_ref>
  qref.pair cx %a, %b : !qcc.qubit_ref
  return
}
