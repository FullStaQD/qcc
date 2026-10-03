// RUN: qcc-opt %s --inline | FileCheck %s

// The PrelimHLEP inliner interface allows inlining into haloed contexts
// (including into `prelimhlep.lin` bodies), but refuses to move PrelimHLEP
// ops into non-haloed functions, so haloed callees stay out of classical
// callers.

func.func private @x_gate(%qubit: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %out = prelimhlep.lin (%b : i1 from %qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant 1 : i1
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%nb : i1)
    }
    return %out : !prelimhlep.lin<i1>
}

// A haloed callee inlines into another haloed function, including into the
// `scf.if` inside a `prelimhlep.lin` body (the nested-lin shape the
// QCO conversion's conditional-unitary pattern consumes).

func.func @cnot(%control : !prelimhlep.lin<i1>, %target : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %oc, %ot = prelimhlep.lin (%cb : i1 from %control : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %new_target = scf.if %cb -> (!prelimhlep.lin<i1>) {
            %flipped = func.call @x_gate(%target) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
            scf.yield %flipped : !prelimhlep.lin<i1>
        } else {
            scf.yield %target : !prelimhlep.lin<i1>
        }
        prelimhlep.output (%cb : i1) carrying (%new_target : !prelimhlep.lin<i1>)
    }
    return %oc, %ot : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @cnot
// CHECK:         scf.if
// CHECK-NOT:       func.call
// CHECK:           prelimhlep.lin
// CHECK:             arith.xori
// CHECK:         prelimhlep.output

// A haloed callee is NOT inlined into a non-haloed (classical) function:
// the call must survive.

func.func @haloed(%qubit : !prelimhlep.lin<i1>) -> i1 attributes { prelimhlep.halo } {
    %m = prelimhlep.lin (%b : i1 from %qubit : !prelimhlep.lin<i1>) -> (i1) {
        prelimhlep.output () carrying (%b : i1)
    }
    return %m : i1
}

func.func @classical(%qubit : !prelimhlep.lin<i1>) -> i1 {
    %r = func.call @haloed(%qubit) : (!prelimhlep.lin<i1>) -> i1
    return %r : i1
}

// CHECK-LABEL: func.func @classical
// CHECK:         call @haloed
