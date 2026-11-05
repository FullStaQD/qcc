// RUN: qcc-opt %s --canonicalize | FileCheck %s

// An unused coin flip is not dead code.
// TODO: It should be.

// CHECK-LABEL: func.func @unused_coin_flip
// CHECK:         hlep.lin () -> (i1)
func.func @unused_coin_flip(%u : !hlep.unit) -> !hlep.unit attributes { hlep.halo } {
    %r = hlep.lin () -> (i1) {
        %p = hlep.lin () -> (!hlep.lin<!hlep.x<1>>) {
            %c = hlep.constant "+" : !hlep.x<1>
            hlep.output (%c : !hlep.x<1>)
        }
        %z = hlep.base_change %p : !hlep.lin<!hlep.x<1>> -> !hlep.lin<i1>
        %b = hlep.lin (%zb : i1 from %z : !hlep.lin<i1>) -> (i1) {
            hlep.output () carrying (%zb : i1)
        }
        hlep.output () carrying (%b : i1)
    }
    return %u : !hlep.unit
}

// CHECK-LABEL: func.func @unused_pure_lin
// CHECK-NOT:     hlep.lin
// CHECK:         return
func.func @unused_pure_lin(%u : !hlep.unit, %a : i1) -> !hlep.unit attributes { hlep.halo } {
    %r = hlep.lin () -> (i1) {
        %x = arith.xori %a, %a : i1
        hlep.output () carrying (%x : i1)
    }
    return %u : !hlep.unit
}

// A phase acts on the quantum state, not on the value: it is not dead even
// if its result is unused.

// CHECK-LABEL: func.func @unused_phase
// CHECK:         hlep.add_phase
func.func @unused_phase(%s : !hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo } {
    %o = hlep.lin (%b : i1 from %s : !hlep.lin<i1>) -> (!hlep.lin<i1>) {
        %pi = arith.constant 3.141592653589793 : f64
        %p = hlep.add_phase %pi, %b : (f64, i1) -> i1
        hlep.output (%b : i1)
    }
    return %o : !hlep.lin<i1>
}
