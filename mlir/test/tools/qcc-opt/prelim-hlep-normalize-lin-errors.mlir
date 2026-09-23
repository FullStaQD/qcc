// RUN: qcc-opt %s --prelim-hlep-normalize-lin --split-input-file --verify-diagnostics

// Arithmetic that mixes input bits is general reversible synthesis, which
// the pattern library does not attempt.

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
