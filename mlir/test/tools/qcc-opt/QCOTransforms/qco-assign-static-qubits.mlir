// RUN: qcc-opt %s --qco-assign-static-qubits --split-input-file | FileCheck %s

// Indices are handed out in walk order, starting at zero.

// CHECK-LABEL: func.func @three_qubits
func.func @three_qubits() {
    %q0 = qco.alloc : !qco.qubit
    %q1 = qco.alloc : !qco.qubit
    %q2 = qco.alloc : !qco.qubit
    qco.sink %q0 : !qco.qubit
    qco.sink %q1 : !qco.qubit
    qco.sink %q2 : !qco.qubit
    return
}

// CHECK:         %[[Q0:.*]] = qco.static 0 : !qco.qubit
// CHECK:         %[[Q1:.*]] = qco.static 1 : !qco.qubit
// CHECK:         %[[Q2:.*]] = qco.static 2 : !qco.qubit
// CHECK-NOT:     qco.alloc

// -----

// A qubit whose lifetime has ended does not give its index back: the counter
// only ever moves forward, so the second allocation is qubit 1 rather than a
// reuse of qubit 0.

// CHECK-LABEL: func.func @no_reuse_after_sink
func.func @no_reuse_after_sink() {
    %q0 = qco.alloc : !qco.qubit
    qco.sink %q0 : !qco.qubit
    %q1 = qco.alloc : !qco.qubit
    qco.sink %q1 : !qco.qubit
    return
}

// CHECK:         qco.static 0 : !qco.qubit
// CHECK:         qco.static 1 : !qco.qubit

// -----

// The counter is module-wide, so two functions never name the same qubit,
// whether or not the callee has been inlined.

func.func @first() {
    %q = qco.alloc : !qco.qubit
    qco.sink %q : !qco.qubit
    return
}

func.func @second() {
    %q = qco.alloc : !qco.qubit
    qco.sink %q : !qco.qubit
    return
}

// CHECK:         func.func @first
// CHECK:           qco.static 0 : !qco.qubit
// CHECK:         func.func @second
// CHECK:           qco.static 1 : !qco.qubit

// -----

// An already-static program is left alone.

// CHECK-LABEL: func.func @already_static
func.func @already_static() {
    %q = qco.static 7 : !qco.qubit
    qco.sink %q : !qco.qubit
    return
}

// CHECK:         qco.static 7 : !qco.qubit
