// RUN: qcc-opt %s --prelim-hlep-lin-to-gates --split-input-file --verify-diagnostics

// Arithmetic that mixes input bits is general reversible synthesis, which
// peeling does not attempt.

func.func @add(%a : !prelimhlep.lin<i2>, %b : !prelimhlep.lin<i2>) -> !prelimhlep.lin<i2> attributes { prelimhlep.halo } {
    %sum = prelimhlep.lin (
        %ab : i2 from %a : !prelimhlep.lin<i2>,
        %bb : i2 from %b : !prelimhlep.lin<i2>
    ) -> (!prelimhlep.lin<i2>) {
        // expected-error @below {{unrecognized op in prelimhlep.lin body}}
        %s = arith.addi %ab, %bb : i2
        prelimhlep.output (%s : i2)
    }
    return %sum : !prelimhlep.lin<i2>
}

// -----

// An indirect call on a function value can only be lowered after inlining
// has made the callee concrete (this is the standalone `@phase_tag_4`
// shape from the advanced test).

func.func @oracle_call(%state : !prelimhlep.lin<i2>, %oracle : (i2) -> i1) -> (!prelimhlep.lin<i2>, i1) attributes { prelimhlep.halo } {
    %out, %bit = prelimhlep.lin (%bits : i2 from %state : !prelimhlep.lin<i2>) -> (!prelimhlep.lin<i2>, i1) {
        // expected-error @below {{indirect call inside prelimhlep.lin body; requires inlining a constant callee}}
        %r = func.call_indirect %oracle(%bits) : (i2) -> i1
        prelimhlep.output (%bits : i2) carrying (%r : i1)
    }
    return %out, %bit : !prelimhlep.lin<i2>, i1
}

// -----

// Calls inside lin bodies must have been inlined away.

func.func @is_zero(%x : i1) -> i1 {
    %true = arith.constant true
    %r = arith.xori %x, %true : i1
    return %r : i1
}

func.func @classical_call(%state : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) attributes { prelimhlep.halo } {
    %out, %bit = prelimhlep.lin (%b : i1 from %state : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
        // expected-error @below {{call inside prelimhlep.lin body survived inlining}}
        %r = func.call @is_zero(%b) : (i1) -> i1
        prelimhlep.output (%b : i1) carrying (%r : i1)
    }
    return %out, %bit : !prelimhlep.lin<i1>, i1
}

// -----

// Deleting a qubit without measuring it is not unitary; automatic
// uncomputation is out of scope.

func.func @discard(%qubit : !prelimhlep.lin<i1>, %keep : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    // expected-error @below {{unrecognized prelimhlep.lin body: input bit is discarded without measurement}}
    %out = prelimhlep.lin (
        %b : i1 from %qubit : !prelimhlep.lin<i1>,
        %k : i1 from %keep : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i1>) {
        prelimhlep.output (%k : i1)
    }
    return %out : !prelimhlep.lin<i1>
}

// -----

// Copying a qubit is the linearization of the classical copy; it would
// need an allocation and a CNOT, which the peeling does not synthesize.

func.func @copy(%qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    // expected-error @below {{unrecognized prelimhlep.lin body: input bit used in more than one output}}
    %a, %b = prelimhlep.lin (%x : i1 from %qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        prelimhlep.output (%x : i1, %x : i1)
    }
    return %a, %b : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// -----

// A CNOT written as bit logic combines two input bits.

func.func @xor(%a : !prelimhlep.lin<i1>, %b : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %oa, %ob = prelimhlep.lin (%x : i1 from %a : !prelimhlep.lin<i1>, %y : i1 from %b : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        // expected-error @below {{'xor' of two input bits}}
        %s = arith.xori %x, %y : i1
        prelimhlep.output (%x : i1, %s : i1)
    }
    return %oa, %ob : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// -----

// A branch that permutes captured values is a controlled SWAP, not a
// sequence of controlled single-qubit gates.

func.func @controlled_swap(%c : !prelimhlep.lin<i1>, %a : !prelimhlep.lin<i1>, %b : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    // expected-error @below {{unrecognized prelimhlep.lin body: controlled sub-circuit permutes its wires}}
    %oc, %oa, %ob = prelimhlep.lin (%cb : i1 from %c : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %r:2 = scf.if %cb -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
            scf.yield %b, %a : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
        } else {
            scf.yield %a, %b : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
        }
        prelimhlep.output (%cb : i1) carrying (%r#0 : !prelimhlep.lin<i1>, %r#1 : !prelimhlep.lin<i1>)
    }
    return %oc, %oa, %ob : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// -----

// Measurements under a condition are not supported yet.

func.func @controlled_measurement(%c : !prelimhlep.lin<i1>, %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %oc, %ot = prelimhlep.lin (%cb : i1 from %c : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %r = scf.if %cb -> (!prelimhlep.lin<i1>) {
            // expected-error @below {{'hlepgate.measure' is not a unitary gate and cannot be applied under a condition}}
            %q, %m = prelimhlep.lin (%tb : i1 from %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
                prelimhlep.output (%tb : i1) carrying (%tb : i1)
            }
            scf.yield %q : !prelimhlep.lin<i1>
        } else {
            scf.yield %t : !prelimhlep.lin<i1>
        }
        prelimhlep.output (%cb : i1) carrying (%r : !prelimhlep.lin<i1>)
    }
    return %oc, %ot : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}
