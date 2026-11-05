// RUN: qcc-opt %s --loop-invariant-code-motion | FileCheck %s

// Ten coin flips in a loop stay ten coin flips.

// CHECK-LABEL: func.func @coin_flips_in_loop
// CHECK:         scf.for
// CHECK-NEXT:      hlep.lin () -> (i1)
func.func @coin_flips_in_loop(%u : !hlep.unit) -> i1 attributes { hlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c10 = arith.constant 10 : index
    %false = arith.constant false
    %parity = scf.for %i = %c0 to %c10 step %c1 iter_args(%acc = %false) -> (i1) {
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
        %next = arith.xori %acc, %r : i1
        scf.yield %next : i1
    }
    return %parity : i1
}

// The pure `lin` is loop invariant and hoisted.

// CHECK-LABEL: func.func @pure_lin_in_loop
// CHECK:         hlep.lin () -> (i1)
// CHECK:         scf.for
func.func @pure_lin_in_loop(%u : !hlep.unit, %a : i1) -> i1 attributes { hlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c10 = arith.constant 10 : index
    %false = arith.constant false
    %parity = scf.for %i = %c0 to %c10 step %c1 iter_args(%acc = %false) -> (i1) {
        %r = hlep.lin () -> (i1) {
            %x = arith.xori %a, %a : i1
            hlep.output () carrying (%x : i1)
        }
        %next = arith.xori %acc, %r : i1
        scf.yield %next : i1
    }
    return %parity : i1
}
