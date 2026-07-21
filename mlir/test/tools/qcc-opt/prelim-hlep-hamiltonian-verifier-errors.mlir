// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// Tests for the `#prelimhlep.hamiltonian` attribute's own verifier (see
// HamiltonianAttr.cpp), independent of any op it's attached to. (The
// "at least one term" check is not exercised here: the grammar itself
// requires a term after the leading `qubitCount,`, so it is unreachable
// from this textual syntax and only guards non-textual construction.)

func.func private @hamiltonian_nonpositive_qubit_count() attributes {
    // expected-error @below {{expected a positive qubit count, got 0}}
    test.attr = #prelimhlep.hamiltonian<0, Z[0]>
}

// -----

func.func private @hamiltonian_qubit_out_of_range() attributes {
    // expected-error @below {{term #0 factor qubit index 1 is out of range for qubit count 1}}
    test.attr = #prelimhlep.hamiltonian<1, Z[1]>
}

// -----

func.func private @hamiltonian_repeated_qubit_in_term() attributes {
    // expected-error @below {{term #0 has more than one Pauli factor on qubit 0}}
    test.attr = #prelimhlep.hamiltonian<1, X[0] * Z[0]>
}

// -----

func.func private @hamiltonian_zero_coefficient() attributes {
    // expected-error @below {{term #0 has a zero coefficient}}
    test.attr = #prelimhlep.hamiltonian<1, 0.0 * Z[0]>
}

// -----

func.func private @hamiltonian_duplicate_term() attributes {
    // expected-error @below {{term #1 duplicates an earlier term (up to reordering of its factors)}}
    test.attr = #prelimhlep.hamiltonian<2, X[0] * Z[1] + Z[1] * X[0]>
}
