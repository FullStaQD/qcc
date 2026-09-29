// RUN: qcc-opt %s --cse | FileCheck %s --check-prefix=CSE
// RUN: qcc-opt %s --loop-invariant-code-motion | FileCheck %s --check-prefix=LICM
// RUN: qcc-opt %s --canonicalize | FileCheck %s --check-prefix=DCE

// Side effects of `prelimhlep.lin` (see PrelimHLEPEffects.td). A coin flip
// consumes no linear value, so linearity does not keep it apart from
// another one. Only its nested measurement, which reads and writes the
// hidden world index, keeps it from being merged, hoisted, or erased.

// CSE-LABEL: func.func @two_coin_flips
// CSE-COUNT-2: prelimhlep.base_change
// CSE-NOT:     prelimhlep.base_change
func.func @two_coin_flips(%u : !prelimhlep.unit) -> (i1, i1) attributes { prelimhlep.halo } {
    %r0 = prelimhlep.lin () -> (i1) {
        %p = prelimhlep.constant "+" : !prelimhlep.lin<!prelimhlep.x<1>>
        %z = prelimhlep.base_change %p : !prelimhlep.lin<!prelimhlep.x<1>> -> !prelimhlep.lin<i1>
        %b = prelimhlep.lin (%zb : i1 from %z : !prelimhlep.lin<i1>) -> (i1) {
            prelimhlep.output () carrying (%zb : i1)
        }
        prelimhlep.output () carrying (%b : i1)
    }
    %r1 = prelimhlep.lin () -> (i1) {
        %p = prelimhlep.constant "+" : !prelimhlep.lin<!prelimhlep.x<1>>
        %z = prelimhlep.base_change %p : !prelimhlep.lin<!prelimhlep.x<1>> -> !prelimhlep.lin<i1>
        %b = prelimhlep.lin (%zb : i1 from %z : !prelimhlep.lin<i1>) -> (i1) {
            prelimhlep.output () carrying (%zb : i1)
        }
        prelimhlep.output () carrying (%b : i1)
    }
    return %r0, %r1 : i1, i1
}

// Two allocations of the same constant must not become one linear value.

// CSE-LABEL: func.func @two_constants
// CSE-COUNT-2: prelimhlep.constant "+"
func.func @two_constants(%u : !prelimhlep.unit) -> (!prelimhlep.lin<!prelimhlep.x<1>>, !prelimhlep.lin<!prelimhlep.x<1>>) attributes { prelimhlep.halo } {
    %p0 = prelimhlep.constant "+" : !prelimhlep.lin<!prelimhlep.x<1>>
    %p1 = prelimhlep.constant "+" : !prelimhlep.lin<!prelimhlep.x<1>>
    return %p0, %p1 : !prelimhlep.lin<!prelimhlep.x<1>>, !prelimhlep.lin<!prelimhlep.x<1>>
}

// A `lin` without worlds, allocations, or frees is pure: here, one that
// only computes on captured classical values.

// CSE-LABEL: func.func @pure_lin(
// CSE:         [[R:%.+]] = prelimhlep.lin
// CSE-NOT:     prelimhlep.lin
// CSE:         return [[R]], [[R]]
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

// Ten coin flips in a loop stay ten coin flips.

// LICM-LABEL: func.func @coin_flips_in_loop
// LICM:         scf.for
// LICM-NEXT:      prelimhlep.lin () -> (i1)
func.func @coin_flips_in_loop(%u : !prelimhlep.unit) -> i1 attributes { prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c10 = arith.constant 10 : index
    %false = arith.constant false
    %parity = scf.for %i = %c0 to %c10 step %c1 iter_args(%acc = %false) -> (i1) {
        %r = prelimhlep.lin () -> (i1) {
            %p = prelimhlep.constant "+" : !prelimhlep.lin<!prelimhlep.x<1>>
            %z = prelimhlep.base_change %p : !prelimhlep.lin<!prelimhlep.x<1>> -> !prelimhlep.lin<i1>
            %b = prelimhlep.lin (%zb : i1 from %z : !prelimhlep.lin<i1>) -> (i1) {
                prelimhlep.output () carrying (%zb : i1)
            }
            prelimhlep.output () carrying (%b : i1)
        }
        %next = arith.xori %acc, %r : i1
        scf.yield %next : i1
    }
    return %parity : i1
}

// The pure `lin` is loop invariant and hoisted.

// LICM-LABEL: func.func @pure_lin_in_loop
// LICM:         prelimhlep.lin () -> (i1)
// LICM:         scf.for
func.func @pure_lin_in_loop(%u : !prelimhlep.unit, %a : i1) -> i1 attributes { prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c10 = arith.constant 10 : index
    %false = arith.constant false
    %parity = scf.for %i = %c0 to %c10 step %c1 iter_args(%acc = %false) -> (i1) {
        %r = prelimhlep.lin () -> (i1) {
            %x = arith.xori %a, %a : i1
            prelimhlep.output () carrying (%x : i1)
        }
        %next = arith.xori %acc, %r : i1
        scf.yield %next : i1
    }
    return %parity : i1
}

// An unused coin flip is not dead code, a measurement of a captured bit that
// is ignored afterwards is, since the latter has a single world.

// DCE-LABEL: func.func @unused_coin_flip
// DCE:         prelimhlep.lin () -> (i1)
func.func @unused_coin_flip(%u : !prelimhlep.unit) -> !prelimhlep.unit attributes { prelimhlep.halo } {
    %r = prelimhlep.lin () -> (i1) {
        %p = prelimhlep.constant "+" : !prelimhlep.lin<!prelimhlep.x<1>>
        %z = prelimhlep.base_change %p : !prelimhlep.lin<!prelimhlep.x<1>> -> !prelimhlep.lin<i1>
        %b = prelimhlep.lin (%zb : i1 from %z : !prelimhlep.lin<i1>) -> (i1) {
            prelimhlep.output () carrying (%zb : i1)
        }
        prelimhlep.output () carrying (%b : i1)
    }
    return %u : !prelimhlep.unit
}

// DCE-LABEL: func.func @unused_pure_lin
// DCE-NOT:     prelimhlep.lin
// DCE:         return
func.func @unused_pure_lin(%u : !prelimhlep.unit, %a : i1) -> !prelimhlep.unit attributes { prelimhlep.halo } {
    %r = prelimhlep.lin () -> (i1) {
        %x = arith.xori %a, %a : i1
        prelimhlep.output () carrying (%x : i1)
    }
    return %u : !prelimhlep.unit
}
