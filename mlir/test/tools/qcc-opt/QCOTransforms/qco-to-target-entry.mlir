// RUN: qcc-opt %s --split-input-file --pass-pipeline='builtin.module(decompose-multi-controlled,qco-assign-static-qubits,qco-to-qc,symbol-dce)' | FileCheck %s

// The three passes `buildQCOLoweringPipeline` puts between QCO and a target,
// on the shape that motivates them: Grover's phase tag is a Z with three
// controls, which no backend has an instruction for.
//
// `test/tools/qcc/mojo-frontend-to-qir.mlir` is the same sequence reached
// through the driver, on a kernel small enough to check the QIR output of.

// CHECK-LABEL: func.func @multi_controlled
func.func @multi_controlled() {
    %q0 = qco.alloc : !qco.qubit
    %q1 = qco.alloc : !qco.qubit
    %q2 = qco.alloc : !qco.qubit
    %q3 = qco.alloc : !qco.qubit

    %c:3, %t = qco.ctrl(%q0, %q1, %q2) targets (%a = %q3) {
      %z = qco.z %a : !qco.qubit -> !qco.qubit
      qco.yield %z : !qco.qubit
    } : ({!qco.qubit, !qco.qubit, !qco.qubit}, {!qco.qubit}) -> ({!qco.qubit, !qco.qubit, !qco.qubit}, {!qco.qubit})

    qco.sink %c#0 : !qco.qubit
    qco.sink %c#1 : !qco.qubit
    qco.sink %c#2 : !qco.qubit
    qco.sink %t : !qco.qubit
    return
}

// Allocation became a register file, addressed by index.
// CHECK:         qc.static 0 : !qc.qubit
// CHECK:         qc.static 1 : !qc.qubit
// CHECK:         qc.static 2 : !qc.qubit
// CHECK:         qc.static 3 : !qc.qubit
// CHECK-NOT:     qc.alloc

// The four-qubit controlled Z is gone, and what is left is a gate set a
// backend has instructions for.
// CHECK-NOT:     qco.

// -----

// A private helper nothing calls does not survive to the target, because the
// QIR lowering cannot lower a qubit that arrives as a function argument.

func.func private @unused(%q: !qco.qubit) -> !qco.qubit {
    %x = qco.x %q : !qco.qubit -> !qco.qubit
    return %x : !qco.qubit
}

func.func @entry() {
    %q = qco.alloc : !qco.qubit
    qco.sink %q : !qco.qubit
    return
}

// CHECK-NOT:     @unused
// CHECK-LABEL: func.func @entry
