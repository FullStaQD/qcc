// RUN: qcc-opt %s --prelim-hlep-to-qco --split-input-file --verify-diagnostics

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

// The conversion only understands normal-form (tagged) lin ops.

func.func @untagged(%qubit : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    // expected-error @below {{prelimhlep.lin is not in normal form; run --prelim-hlep-normalize-lin first}}
    %out = prelimhlep.lin (%b : i1 from %qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant 1 : i1
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%nb : i1)
    }
    return %out : !prelimhlep.lin<i1>
}
