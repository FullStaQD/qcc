// RUN: qcc-opt %s --canonicalize | FileCheck %s

// An unused coin flip is not dead code.
// TODO: It should be.

// CHECK-LABEL: func.func @unused_coin_flip
// CHECK:         prelimhlep.lin () -> (i1)
func.func @unused_coin_flip(%u : !prelimhlep.unit) -> !prelimhlep.unit attributes { prelimhlep.halo } {
    %r = prelimhlep.lin () -> (i1) {
        %p = prelimhlep.lin () -> (!prelimhlep.lin<!prelimhlep.x<1>>) {
            %c = prelimhlep.constant "+" : !prelimhlep.x<1>
            prelimhlep.output (%c : !prelimhlep.x<1>)
        }
        %z = prelimhlep.base_change %p : !prelimhlep.lin<!prelimhlep.x<1>> -> !prelimhlep.lin<i1>
        %b = prelimhlep.lin (%zb : i1 from %z : !prelimhlep.lin<i1>) -> (i1) {
            prelimhlep.output () carrying (%zb : i1)
        }
        prelimhlep.output () carrying (%b : i1)
    }
    return %u : !prelimhlep.unit
}

// CHECK-LABEL: func.func @unused_pure_lin
// CHECK-NOT:     prelimhlep.lin
// CHECK:         return
func.func @unused_pure_lin(%u : !prelimhlep.unit, %a : i1) -> !prelimhlep.unit attributes { prelimhlep.halo } {
    %r = prelimhlep.lin () -> (i1) {
        %x = arith.xori %a, %a : i1
        prelimhlep.output () carrying (%x : i1)
    }
    return %u : !prelimhlep.unit
}

// A phase acts on the quantum state, not on the value: it is not dead even
// if its result is unused.

// CHECK-LABEL: func.func @unused_phase
// CHECK:         prelimhlep.add_phase
func.func @unused_phase(%s : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %o = prelimhlep.lin (%b : i1 from %s : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %pi = arith.constant 3.141592653589793 : f64
        %p = prelimhlep.add_phase %pi, %b : (f64, i1) -> i1
        prelimhlep.output (%b : i1)
    }
    return %o : !prelimhlep.lin<i1>
}
