// RUN: qcc-opt %s --cse | FileCheck %s

// Two coin flips: It's important that the duplicate code stays duplicate.

// CHECK-LABEL: func.func @two_coin_flips
// CHECK-COUNT-2: prelimhlep.base_change
// CHECK-NOT:     prelimhlep.base_change
func.func @two_coin_flips(%u : !prelimhlep.unit) -> (i1, i1) attributes { prelimhlep.halo } {
    %r0 = prelimhlep.lin () -> (i1) {
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
    %r1 = prelimhlep.lin () -> (i1) {
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
    return %r0, %r1 : i1, i1
}

// Classical + values may be CSE'd.

// CHECK-LABEL: func.func @two_constants
// CHECK-COUNT-1: prelimhlep.constant "+"
// CHECK-NOT:     prelimhlep.constant
func.func @two_constants(%u : !prelimhlep.unit) -> (!prelimhlep.x<1>, !prelimhlep.x<1>) attributes { prelimhlep.halo } {
    %c0 = prelimhlep.constant "+" : !prelimhlep.x<1>
    %c1 = prelimhlep.constant "+" : !prelimhlep.x<1>
    return %c0, %c1 : !prelimhlep.x<1>, !prelimhlep.x<1>
}

// Linearized classical + values may not be CSE'd.

// CHECK-LABEL: func.func @two_linearized_constants
// CHECK-COUNT-2: prelimhlep.lin ()
// CHECK-NOT:     prelimhlep.lin ()
func.func @two_linearized_constants(%u : !prelimhlep.unit) -> (!prelimhlep.lin<!prelimhlep.x<1>>, !prelimhlep.lin<!prelimhlep.x<1>>) attributes { prelimhlep.halo } {
    %p0 = prelimhlep.lin () -> (!prelimhlep.lin<!prelimhlep.x<1>>) {
        %c = prelimhlep.constant "+" : !prelimhlep.x<1>
        prelimhlep.output (%c : !prelimhlep.x<1>)
    }
    %p1 = prelimhlep.lin () -> (!prelimhlep.lin<!prelimhlep.x<1>>) {
        %c = prelimhlep.constant "+" : !prelimhlep.x<1>
        prelimhlep.output (%c : !prelimhlep.x<1>)
    }
    return %p0, %p1 : !prelimhlep.lin<!prelimhlep.x<1>>, !prelimhlep.lin<!prelimhlep.x<1>>
}

// A `lin` without worlds, allocations, or frees is pure: here, one that
// only computes on captured classical values.

// CHECK-LABEL: func.func @pure_lin(
// CHECK:         [[R:%.+]] = prelimhlep.lin
// CHECK-NOT:     prelimhlep.lin
// CHECK:         return [[R]], [[R]]
func.func @pure_lin(%u : !prelimhlep.unit, %a : i1) -> (i1, i1) attributes { prelimhlep.halo } {
    %r0 = prelimhlep.lin () -> (i1) {
        %x = arith.xori %a, %a : i1
        prelimhlep.output () carrying (%x : i1)
    }
    %r1 = prelimhlep.lin () -> (i1) {
        %x = arith.xori %a, %a : i1
        prelimhlep.output () carrying (%x : i1)
    }
    return %r0, %r1 : i1, i1
}
