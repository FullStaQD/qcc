// RUN: qcc-opt %s --qref-assign-qubits --split-input-file | FileCheck %s

// Indices are handed out in walk order, and an array becomes a `tensor.from_elements` of its qubits.
// CHECK-LABEL: func.func @numbering
func.func @numbering(%cond: i1) {
  %c2 = arith.constant 2 : index
  %a = qcc.alloc : !qcc.qubit_ref
  %r = qcc.alloc %c2 : tensor<?x!qcc.qubit_ref>
  %s = qcc.alloc : tensor<2x!qcc.qubit_ref>
  scf.if %cond {
    %b = qcc.alloc : !qcc.qubit_ref
    qref.single x %b : !qcc.qubit_ref
  }
  %e = qcc.alloc : tensor<0x!qcc.qubit_ref>
  qref.single h %a : !qcc.qubit_ref
  return
}

// CHECK:      %[[A:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT: %[[R0:.*]] = qcc.static_ref [1] : !qcc.qubit_ref
// CHECK-NEXT: %[[R1:.*]] = qcc.static_ref [2] : !qcc.qubit_ref
// CHECK-NEXT: %[[R:.*]] = tensor.from_elements %[[R0]], %[[R1]] : tensor<2x!qcc.qubit_ref>
// CHECK-NEXT: tensor.cast %[[R]] : tensor<2x!qcc.qubit_ref> to tensor<?x!qcc.qubit_ref>
// CHECK-NEXT: %[[S0:.*]] = qcc.static_ref [3] : !qcc.qubit_ref
// CHECK-NEXT: %[[S1:.*]] = qcc.static_ref [4] : !qcc.qubit_ref
// CHECK-NEXT: tensor.from_elements %[[S0]], %[[S1]] : tensor<2x!qcc.qubit_ref>
// CHECK-NEXT: scf.if
// CHECK-NEXT:   %[[B:.*]] = qcc.static_ref [5] : !qcc.qubit_ref
// CHECK-NEXT:   qref.single x %[[B]] : !qcc.qubit_ref
// CHECK-NEXT: }
// CHECK-NEXT: tensor.from_elements  : tensor<0x!qcc.qubit_ref>
// CHECK-NEXT: qref.single h %[[A]] : !qcc.qubit_ref

// -----

// An index that a `qcc.static_ref` names is never handed out, wherever the `qcc.static_ref` sits.
// CHECK-LABEL: func.func @reserved
func.func @reserved() {
  %a = qcc.alloc : tensor<3x!qcc.qubit_ref>
  %q1 = qcc.static_ref [1] : !qcc.qubit_ref
  %q3 = qcc.static_ref [3] : !qcc.qubit_ref
  return
}

// CHECK:      %[[A0:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT: %[[A1:.*]] = qcc.static_ref [2] : !qcc.qubit_ref
// CHECK-NEXT: %[[A2:.*]] = qcc.static_ref [4] : !qcc.qubit_ref
// CHECK-NEXT: tensor.from_elements %[[A0]], %[[A1]], %[[A2]] : tensor<3x!qcc.qubit_ref>

// -----

// An allocation reuses freed qubits and resets them: those of the most recent dealloc first, in array order.
// CHECK-LABEL: func.func @reuse
func.func @reuse() {
  %r = qcc.alloc : tensor<2x!qcc.qubit_ref>
  %a = qcc.alloc : !qcc.qubit_ref
  %cast = tensor.cast %r : tensor<2x!qcc.qubit_ref> to tensor<?x!qcc.qubit_ref>
  qcc.dealloc %cast : tensor<?x!qcc.qubit_ref>
  qcc.dealloc %a : !qcc.qubit_ref
  %s = qcc.alloc : tensor<4x!qcc.qubit_ref>
  return
}

// CHECK:      qcc.static_ref [0]
// CHECK-NEXT: qcc.static_ref [1]
// CHECK-NEXT: tensor.from_elements
// CHECK-NEXT: qcc.static_ref [2]
// CHECK-NEXT: tensor.cast
// CHECK-NEXT: %[[S0:.*]] = qcc.static_ref [2] : !qcc.qubit_ref
// CHECK-NEXT: qref.reset z %[[S0]] : !qcc.qubit_ref
// CHECK-NEXT: %[[S1:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT: qref.reset z %[[S1]] : !qcc.qubit_ref
// CHECK-NEXT: %[[S2:.*]] = qcc.static_ref [1] : !qcc.qubit_ref
// CHECK-NEXT: qref.reset z %[[S2]] : !qcc.qubit_ref
// CHECK-NEXT: %[[S3:.*]] = qcc.static_ref [3] : !qcc.qubit_ref
// CHECK-NEXT: tensor.from_elements %[[S0]], %[[S1]], %[[S2]], %[[S3]] : tensor<4x!qcc.qubit_ref>
// CHECK-NOT:  qcc.dealloc

// -----

// Only a dealloc that dominates the allocation frees qubits for it.
// CHECK-LABEL: func.func @dominance
func.func @dominance(%cond: i1) {
  %a = qcc.alloc : !qcc.qubit_ref
  scf.if %cond {
    qcc.dealloc %a : !qcc.qubit_ref
    %b = qcc.alloc : !qcc.qubit_ref
    qref.single x %b : !qcc.qubit_ref
  }
  %c = qcc.alloc : !qcc.qubit_ref
  qref.single y %c : !qcc.qubit_ref
  return
}

// CHECK:      qcc.static_ref [0]
// CHECK-NEXT: scf.if
// CHECK-NEXT:   %[[B:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:   qref.reset z %[[B]] : !qcc.qubit_ref
// CHECK-NEXT:   qref.single x %[[B]] : !qcc.qubit_ref
// CHECK-NEXT: }
// CHECK-NEXT: %[[C:.*]] = qcc.static_ref [1] : !qcc.qubit_ref
// CHECK-NEXT: qref.single y %[[C]] : !qcc.qubit_ref

// -----

// An allocation in a loop resets its qubits, even fresh ones: the previous iteration leaves them in an unknown state.
// CHECK-LABEL: func.func @loop
func.func @loop(%n: index) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  scf.for %i = %c0 to %n step %c1 {
    %q = qcc.alloc : !qcc.qubit_ref
    qref.single x %q : !qcc.qubit_ref
    qcc.dealloc %q : !qcc.qubit_ref
  }
  return
}

// CHECK:      scf.for
// CHECK-NEXT:   %[[Q:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:   qref.reset z %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:   qref.single x %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT: }

// -----

// CHECK-LABEL: func.func @while
func.func @while(%cond: i1) {
  scf.while : () -> () {
    scf.condition(%cond)
  } do {
    %q = qcc.alloc : !qcc.qubit_ref
    qref.single x %q : !qcc.qubit_ref
    qcc.dealloc %q : !qcc.qubit_ref
    scf.yield
  }
  return
}

// CHECK:      } do {
// CHECK-NEXT:   %[[Q:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:   qref.reset z %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:   qref.single x %[[Q]] : !qcc.qubit_ref

// -----

// A block on a cycle of branches runs repeatedly, too.
// CHECK-LABEL: func.func @branch_cycle
func.func @branch_cycle(%cond: i1) {
  cf.br ^bb1
^bb1:
  %q = qcc.alloc : !qcc.qubit_ref
  qref.single x %q : !qcc.qubit_ref
  qcc.dealloc %q : !qcc.qubit_ref
  cf.cond_br %cond, ^bb1, ^bb2
^bb2:
  return
}

// CHECK:      ^bb1:
// CHECK-NEXT:   %[[Q:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT:   qref.reset z %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:   qref.single x %[[Q]] : !qcc.qubit_ref

// -----

func.func private @classical() {
  return
}

// A call to a function without qubits is fine.
// CHECK-LABEL: func.func @classical_call
func.func @classical_call() {
  %q = qcc.alloc : !qcc.qubit_ref
  func.call @classical() : () -> ()
  qref.single h %q : !qcc.qubit_ref
  return
}

// CHECK:      %[[Q:.*]] = qcc.static_ref [0] : !qcc.qubit_ref
// CHECK-NEXT: call @classical() : () -> ()
// CHECK-NEXT: qref.single h %[[Q]] : !qcc.qubit_ref
