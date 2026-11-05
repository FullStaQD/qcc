// RUN: qcc-opt %s --cse | FileCheck %s

// Two coin flips: It's important that the duplicate code stays duplicate.

// CHECK-LABEL: func.func @two_coin_flips
// CHECK-COUNT-2: hlep.base_change
// CHECK-NOT:     hlep.base_change
func.func @two_coin_flips(%u : !hlep.unit) -> (i1, i1) attributes { hlep.halo } {
    %r0 = hlep.lin () -> (i1) {
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
    %r1 = hlep.lin () -> (i1) {
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
    return %r0, %r1 : i1, i1
}

// Classical + values may be CSE'd.

// CHECK-LABEL: func.func @two_constants
// CHECK-COUNT-1: hlep.constant "+"
// CHECK-NOT:     hlep.constant
func.func @two_constants(%u : !hlep.unit) -> (!hlep.x<1>, !hlep.x<1>) attributes { hlep.halo } {
    %c0 = hlep.constant "+" : !hlep.x<1>
    %c1 = hlep.constant "+" : !hlep.x<1>
    return %c0, %c1 : !hlep.x<1>, !hlep.x<1>
}

// Linearized classical + values may not be CSE'd.

// CHECK-LABEL: func.func @two_linearized_constants
// CHECK-COUNT-2: hlep.lin ()
// CHECK-NOT:     hlep.lin ()
func.func @two_linearized_constants(%u : !hlep.unit) -> (!hlep.lin<!hlep.x<1>>, !hlep.lin<!hlep.x<1>>) attributes { hlep.halo } {
    %p0 = hlep.lin () -> (!hlep.lin<!hlep.x<1>>) {
        %c = hlep.constant "+" : !hlep.x<1>
        hlep.output (%c : !hlep.x<1>)
    }
    %p1 = hlep.lin () -> (!hlep.lin<!hlep.x<1>>) {
        %c = hlep.constant "+" : !hlep.x<1>
        hlep.output (%c : !hlep.x<1>)
    }
    return %p0, %p1 : !hlep.lin<!hlep.x<1>>, !hlep.lin<!hlep.x<1>>
}

// A `lin` without worlds, allocations, or frees is pure: here, one that
// only computes on captured classical values.

// CHECK-LABEL: func.func @pure_lin(
// CHECK:         [[R:%.+]] = hlep.lin
// CHECK-NOT:     hlep.lin
// CHECK:         return [[R]], [[R]]
func.func @pure_lin(%u : !hlep.unit, %a : i1) -> (i1, i1) attributes { hlep.halo } {
    %r0 = hlep.lin () -> (i1) {
        %x = arith.xori %a, %a : i1
        hlep.output () carrying (%x : i1)
    }
    %r1 = hlep.lin () -> (i1) {
        %x = arith.xori %a, %a : i1
        hlep.output () carrying (%x : i1)
    }
    return %r0, %r1 : i1, i1
}

// Two phases on the same delinearized value add up; they must not be merged.

// CHECK-LABEL: func.func @two_phases
// CHECK-COUNT-2: hlep.add_phase
// CHECK-NOT:     hlep.add_phase
func.func @two_phases(%s : !hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo } {
    %o = hlep.lin (%b : i1 from %s : !hlep.lin<i1>) -> (!hlep.lin<i1>) {
        %pi = arith.constant 3.141592653589793 : f64
        %p0 = hlep.add_phase %pi, %b : (f64, i1) -> i1
        %p1 = hlep.add_phase %pi, %b : (f64, i1) -> i1
        %x = arith.xori %p0, %p1 : i1
        %r = arith.xori %x, %b : i1
        hlep.output (%r : i1)
    }
    return %o : !hlep.lin<i1>
}
