// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// Tests for the operand/result type verifiers of `scale`, `add_phase`,
// `base_change`, `constant`, and `exp` (see PrelimHLEPDialect.cpp).

func.func private @scale_mismatched_types(%factor: complex<f64>, %t: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i2>
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{expected result type ('!prelimhlep.lin<i2>') to match input type ('!prelimhlep.lin<i1>')}}
    %0 = "prelimhlep.scale"(%factor, %t) : (complex<f64>, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i2>
    return %0 : !prelimhlep.lin<i2>
}

// -----

func.func private @add_phase_mismatched_types(%alpha: f64, %t: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i2>
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{expected result type ('!prelimhlep.lin<i2>') to match input type ('!prelimhlep.lin<i1>')}}
    %0 = "prelimhlep.add_phase"(%alpha, %t) : (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i2>
    return %0 : !prelimhlep.lin<i2>
}

// -----

func.func private @base_change_not_lin(%t: !prelimhlep.linear_unit) -> !prelimhlep.lin<i1>
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{expected input and result types to be 'lin' types}}
    %0 = prelimhlep.base_change %t : !prelimhlep.linear_unit -> !prelimhlep.lin<i1>
    return %0 : !prelimhlep.lin<i1>
}

// -----

func.func private @base_change_bad_element_type(%t: !prelimhlep.lin<f64>) -> !prelimhlep.lin<i1>
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{expected input type's element type ('f64') to be an integer, 'x', or 'y' type}}
    %0 = prelimhlep.base_change %t : !prelimhlep.lin<f64> -> !prelimhlep.lin<i1>
    return %0 : !prelimhlep.lin<i1>
}

// -----

func.func private @base_change_mismatched_n(%t: !prelimhlep.lin<i1>) -> !prelimhlep.lin<!prelimhlep.x<2>>
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{expected input and result types to have the same qubit count, got 1 and 2}}
    %0 = prelimhlep.base_change %t : !prelimhlep.lin<i1> -> !prelimhlep.lin<!prelimhlep.x<2>>
    return %0 : !prelimhlep.lin<!prelimhlep.x<2>>
}

// -----

func.func private @constant_x_wrong_length() -> !prelimhlep.lin<!prelimhlep.x<3>> {
    // expected-error @below {{expected a length-3 string for result type '!prelimhlep.lin<!prelimhlep.x<3>>', got length 2}}
    %0 = prelimhlep.constant "++" : !prelimhlep.lin<!prelimhlep.x<3>>
    return %0 : !prelimhlep.lin<!prelimhlep.x<3>>
}

// -----

func.func private @constant_x_bad_symbol() -> !prelimhlep.lin<!prelimhlep.x<3>> {
    // expected-error @below {{expected only '+'/'-' symbols for result type '!prelimhlep.lin<!prelimhlep.x<3>>', got 'a'}}
    %0 = prelimhlep.constant "+-a" : !prelimhlep.lin<!prelimhlep.x<3>>
    return %0 : !prelimhlep.lin<!prelimhlep.x<3>>
}

// -----

func.func private @constant_y_wrong_length() -> !prelimhlep.lin<!prelimhlep.y<3>> {
    // expected-error @below {{expected a length-6 string (3 '->'/'<-' symbols) for result type '!prelimhlep.lin<!prelimhlep.y<3>>', got length 2}}
    %0 = prelimhlep.constant "->" : !prelimhlep.lin<!prelimhlep.y<3>>
    return %0 : !prelimhlep.lin<!prelimhlep.y<3>>
}

// -----

func.func private @constant_y_bad_symbol() -> !prelimhlep.lin<!prelimhlep.y<2>> {
    // expected-error @below {{expected only '->'/'<-' symbols for result type '!prelimhlep.lin<!prelimhlep.y<2>>', got 'XY'}}
    %0 = prelimhlep.constant "->XY" : !prelimhlep.lin<!prelimhlep.y<2>>
    return %0 : !prelimhlep.lin<!prelimhlep.y<2>>
}

// -----

func.func private @constant_bad_result_type() -> !prelimhlep.lin<i2> {
    // expected-error @below {{expected result type to be 'lin<x<n>>' or 'lin<y<n>>', got '!prelimhlep.lin<i2>'}}
    %0 = prelimhlep.constant "++" : !prelimhlep.lin<i2>
    return %0 : !prelimhlep.lin<i2>
}

// -----

func.func private @exp_mismatched_types(%theta: f64, %q: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i2>
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{expected result type ('!prelimhlep.lin<i2>') to match input type ('!prelimhlep.lin<i1>')}}
    %0 = "prelimhlep.exp"(%theta, %q) <{hamiltonian = #prelimhlep.hamiltonian<1, []>}> : (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i2>
    return %0 : !prelimhlep.lin<i2>
}

// -----

func.func private @exp_not_purely_quantum(%theta: f64, %q: !prelimhlep.lin<!prelimhlep.x<1>>) -> !prelimhlep.lin<!prelimhlep.x<1>>
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{expected input/result types to be purely-quantum 'lin<i<n>>' types, got '!prelimhlep.lin<!prelimhlep.x<1>>'}}
    %0 = "prelimhlep.exp"(%theta, %q) <{hamiltonian = #prelimhlep.hamiltonian<1, []>}> : (f64, !prelimhlep.lin<!prelimhlep.x<1>>) -> !prelimhlep.lin<!prelimhlep.x<1>>
    return %0 : !prelimhlep.lin<!prelimhlep.x<1>>
}

// -----

func.func private @exp_qubit_count_mismatch(%theta: f64, %q: !prelimhlep.lin<i2>) -> !prelimhlep.lin<i2>
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{expected hamiltonian qubit count (1) to match input/result bit width (2)}}
    %0 = prelimhlep.exp %theta hamiltonian<1, []> %q : (f64, !prelimhlep.lin<i2>) -> !prelimhlep.lin<i2>
    return %0 : !prelimhlep.lin<i2>
}
