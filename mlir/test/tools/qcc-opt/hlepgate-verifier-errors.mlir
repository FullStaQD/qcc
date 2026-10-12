// RUN: qcc-opt %s --split-input-file --verify-diagnostics

func.func @missing_angle(%q : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    // expected-error @below {{expected 1 angle(s) for gate 'rx', got 0}}
    %r = hlepgate.single rx %q
    return %r : !prelimhlep.lin<i1>
}

// -----

func.func @extra_angle(%q : !prelimhlep.lin<i1>, %a : f64) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    // expected-error @below {{expected 0 angle(s) for gate 'h', got 1}}
    %r = hlepgate.single h(%a) %q
    return %r : !prelimhlep.lin<i1>
}

// -----

// Discarding an unmeasured qubit is the linearized discard, which is not
// physical.

func.func @sink_unmeasured(%q : !prelimhlep.lin<i1>) -> !prelimhlep.unit attributes { prelimhlep.halo } {
    // expected-error @below {{expected the qubit to come from a 'hlepgate.measure'}}
    hlepgate.sink %q
    %u = prelimhlep.unit_value : !prelimhlep.unit
    return %u : !prelimhlep.unit
}

// -----

func.func @join_width(%a : !prelimhlep.lin<i1>, %b : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i3> attributes { prelimhlep.halo } {
    // expected-error @below {{expected a register of 2 qubits, got '!prelimhlep.lin<i3>'}}
    %r = hlepgate.join %a, %b : !prelimhlep.lin<i3>
    return %r : !prelimhlep.lin<i3>
}

// -----

func.func @split_non_register(%x : !prelimhlep.lin<!prelimhlep.x<2>>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    // expected-error @below {{expected a '!prelimhlep.lin<i<n>>' register}}
    %q:2 = hlepgate.split %x : !prelimhlep.lin<!prelimhlep.x<2>>
    return %q#0 : !prelimhlep.lin<i1>
}
