// RUN: qcc-opt %s --prelim-hlep-to-qco --split-input-file --verify-diagnostics

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

// Multi-term hamiltonians would need Trotterization.

func.func @exp_multi_term(%theta : f64, %state : !prelimhlep.lin<i3>) -> !prelimhlep.lin<i3> attributes { prelimhlep.halo } {
    // expected-error @below {{multi-term hamiltonians are not supported by the QCO lowering}}
    %out = prelimhlep.exp %theta hamiltonian<3, X[0] * Y[2] + 1.500000e+00 * Z[1]> %state : (f64, !prelimhlep.lin<i3>) -> !prelimhlep.lin<i3>
    return %out : !prelimhlep.lin<i3>
}

// -----

// Mixed-Pauli products have no direct QCO rotation gate.

func.func @exp_mixed_pauli(%theta : f64, %state : !prelimhlep.lin<i2>) -> !prelimhlep.lin<i2> attributes { prelimhlep.halo } {
    // expected-error @below {{only single-Pauli and equal-Pauli-pair hamiltonian terms are supported by the QCO lowering}}
    %out = prelimhlep.exp %theta hamiltonian<2, X[0] * Y[1]> %state : (f64, !prelimhlep.lin<i2>) -> !prelimhlep.lin<i2>
    return %out : !prelimhlep.lin<i2>
}

// -----

// Scaling by a non-unit-modulus factor is not a unitary operation.

func.func @scale_non_unit(%qubit : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %two = complex.constant [2.0, 0.0] : complex<f64>
    // expected-error @below {{non-unit-modulus scale factor cannot be lowered to QCO}}
    %out = prelimhlep.scale %two, %qubit : (complex<f64>, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %out : !prelimhlep.lin<i1>
}

// -----

// The scale factor must be known at compile time.

func.func @scale_non_constant(%factor : complex<f64>, %qubit : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    // expected-error @below {{non-constant scale factor cannot be lowered to QCO}}
    %out = prelimhlep.scale %factor, %qubit : (complex<f64>, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %out : !prelimhlep.lin<i1>
}

// -----

// Quantum control flow at function level (outside a lin body) is not yet
// lowered.

func.func @linear_if(%cond : i1, %a : !prelimhlep.lin<i1>, %b : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    // expected-error @below {{scf.if over linear values outside a prelimhlep.lin body is not yet supported by the QCO lowering}}
    %r:2 = scf.if %cond -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        scf.yield %a, %b : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
    } else {
        scf.yield %b, %a : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
    }
    return %r#0, %r#1 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
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
