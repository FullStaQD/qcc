// RUN: qcc-opt %s --loop-invariant-code-motion | FileCheck %s

// Ten coin flips in a loop stay ten coin flips.

// CHECK-LABEL: func.func @coin_flips_in_loop
// CHECK:         scf.for
// CHECK-NEXT:      prelimhlep.lin () -> (i1)
func.func @coin_flips_in_loop(%u : !prelimhlep.unit) -> i1 attributes { prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c10 = arith.constant 10 : index
    %false = arith.constant false
    %parity = scf.for %i = %c0 to %c10 step %c1 iter_args(%acc = %false) -> (i1) {
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
        %next = arith.xori %acc, %r : i1
        scf.yield %next : i1
    }
    return %parity : i1
}

// The pure `lin` is loop invariant and hoisted.

// CHECK-LABEL: func.func @pure_lin_in_loop
// CHECK:         prelimhlep.lin () -> (i1)
// CHECK:         scf.for
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
