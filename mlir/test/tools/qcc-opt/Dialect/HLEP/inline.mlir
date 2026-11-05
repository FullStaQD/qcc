// RUN: qcc-opt %s --inline | FileCheck %s

// The HLEP inliner interface allows inlining into haloed contexts
// (including into `hlep.lin` bodies), but refuses to move HLEP
// ops into non-haloed functions, so haloed callees stay out of classical
// callers.

func.func private @x_gate(%qubit: !hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo } {
    %out = hlep.lin (%b : i1 from %qubit : !hlep.lin<i1>) -> (!hlep.lin<i1>) {
        %one = arith.constant 1 : i1
        %nb = arith.xori %b, %one : i1
        hlep.output (%nb : i1)
    }
    return %out : !hlep.lin<i1>
}

// A haloed callee inlines into another haloed function, including into the
// `scf.if` inside a `hlep.lin` body (the nested-lin shape the
// QCO conversion's conditional-unitary pattern consumes).

func.func @cnot(%control : !hlep.lin<i1>, %target : !hlep.lin<i1>) -> (!hlep.lin<i1>, !hlep.lin<i1>) attributes { hlep.halo } {
    %oc, %ot = hlep.lin (%cb : i1 from %control : !hlep.lin<i1>) -> (!hlep.lin<i1>, !hlep.lin<i1>) {
        %new_target = scf.if %cb -> (!hlep.lin<i1>) {
            %flipped = func.call @x_gate(%target) : (!hlep.lin<i1>) -> !hlep.lin<i1>
            scf.yield %flipped : !hlep.lin<i1>
        } else {
            scf.yield %target : !hlep.lin<i1>
        }
        hlep.output (%cb : i1) carrying (%new_target : !hlep.lin<i1>)
    }
    return %oc, %ot : !hlep.lin<i1>, !hlep.lin<i1>
}

// CHECK-LABEL: func.func @cnot
// CHECK:         scf.if
// CHECK-NOT:       func.call
// CHECK:           hlep.lin
// CHECK:             arith.xori
// CHECK:         hlep.output

// A haloed callee is NOT inlined into a non-haloed (classical) function:
// the call must survive.

func.func @haloed(%qubit : !hlep.lin<i1>) -> i1 attributes { hlep.halo } {
    %m = hlep.lin (%b : i1 from %qubit : !hlep.lin<i1>) -> (i1) {
        hlep.output () carrying (%b : i1)
    }
    return %m : i1
}

func.func @classical(%qubit : !hlep.lin<i1>) -> i1 {
    %r = func.call @haloed(%qubit) : (!hlep.lin<i1>) -> i1
    return %r : i1
}

// CHECK-LABEL: func.func @classical
// CHECK:         call @haloed
