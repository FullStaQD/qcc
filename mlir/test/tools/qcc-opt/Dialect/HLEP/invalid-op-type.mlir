// RUN: qcc-opt %s --split-input-file --verify-diagnostics

func.func private @add_phase_mismatched_types(%alpha: f64, %t: !hlep.lin<i1>) -> !hlep.lin<i2>
    attributes { hlep.halo = #hlep.halo } {
    // expected-error @below {{expected result type ('!hlep.lin<i2>') to match input type ('!hlep.lin<i1>')}}
    %0 = "hlep.add_phase"(%alpha, %t) : (f64, !hlep.lin<i1>) -> !hlep.lin<i2>
    return %0 : !hlep.lin<i2>
}

// -----

func.func private @base_change_not_lin(%t: !hlep.unit) -> !hlep.lin<i1>
    attributes { hlep.halo = #hlep.halo } {
    // expected-error @below {{expected input and result types to be 'lin' types}}
    %0 = hlep.base_change %t : !hlep.unit -> !hlep.lin<i1>
    return %0 : !hlep.lin<i1>
}

// -----

func.func private @base_change_bad_element_type(%t: !hlep.lin<f64>) -> !hlep.lin<i1>
    attributes { hlep.halo = #hlep.halo } {
    // expected-error @below {{expected input type's element type ('f64') to be an integer, 'x', or 'y' type}}
    %0 = hlep.base_change %t : !hlep.lin<f64> -> !hlep.lin<i1>
    return %0 : !hlep.lin<i1>
}

// -----

func.func private @base_change_mismatched_n(%t: !hlep.lin<i1>) -> !hlep.lin<!hlep.x<2>>
    attributes { hlep.halo = #hlep.halo } {
    // expected-error @below {{expected input and result types to have the same qubit count, got 1 and 2}}
    %0 = hlep.base_change %t : !hlep.lin<i1> -> !hlep.lin<!hlep.x<2>>
    return %0 : !hlep.lin<!hlep.x<2>>
}

// -----

func.func private @constant_x_wrong_length() -> !hlep.x<3> {
    // expected-error @below {{expected a length-3 string for result type '!hlep.x<3>', got length 2}}
    %0 = hlep.constant "++" : !hlep.x<3>
    return %0 : !hlep.x<3>
}

// -----

func.func private @constant_x_bad_symbol() -> !hlep.x<3> {
    // expected-error @below {{expected only '+'/'-' symbols for result type '!hlep.x<3>', got 'a'}}
    %0 = hlep.constant "+-a" : !hlep.x<3>
    return %0 : !hlep.x<3>
}

// -----

func.func private @constant_y_wrong_length() -> !hlep.y<3> {
    // expected-error @below {{expected a length-3 string for result type '!hlep.y<3>', got length 1}}
    %0 = hlep.constant ">" : !hlep.y<3>
    return %0 : !hlep.y<3>
}

// -----

func.func private @constant_y_bad_symbol() -> !hlep.y<2> {
    // expected-error @below {{expected only '>'/'<' symbols for result type '!hlep.y<2>', got '-'}}
    %0 = hlep.constant "->" : !hlep.y<2>
    return %0 : !hlep.y<2>
}

// -----

func.func private @constant_linear_result_type() -> !hlep.lin<!hlep.x<2>> {
    // expected-error @below {{result #0 must be Classical type for length-n strings over the X-basis symbols {+, -}. or Classical type for length-n strings over the Y-basis symbols {>, <}., but got '!hlep.lin<!hlep.x<2>>'}}
    %0 = hlep.constant "++" : !hlep.lin<!hlep.x<2>>
    return %0 : !hlep.lin<!hlep.x<2>>
}

// -----

func.func private @exp_mismatched_types(%theta: f64, %q: !hlep.lin<i1>) -> !hlep.lin<i2>
    attributes { hlep.halo = #hlep.halo } {
    // expected-error @below {{expected result type ('!hlep.lin<i2>') to match input type ('!hlep.lin<i1>')}}
    %0 = "hlep.exp"(%theta, %q) <{hamiltonian = #hlep.hamiltonian<1, Z[0]>}> : (f64, !hlep.lin<i1>) -> !hlep.lin<i2>
    return %0 : !hlep.lin<i2>
}

// -----

func.func private @exp_not_purely_quantum(%theta: f64, %q: !hlep.lin<!hlep.x<1>>) -> !hlep.lin<!hlep.x<1>>
    attributes { hlep.halo = #hlep.halo } {
    // expected-error @below {{expected input/result types to be purely-quantum 'lin<i<n>>' types, got '!hlep.lin<!hlep.x<1>>'}}
    %0 = "hlep.exp"(%theta, %q) <{hamiltonian = #hlep.hamiltonian<1, Z[0]>}> : (f64, !hlep.lin<!hlep.x<1>>) -> !hlep.lin<!hlep.x<1>>
    return %0 : !hlep.lin<!hlep.x<1>>
}

// -----

func.func private @exp_qubit_count_mismatch(%theta: f64, %q: !hlep.lin<i2>) -> !hlep.lin<i2>
    attributes { hlep.halo = #hlep.halo } {
    // expected-error @below {{expected hamiltonian qubit count (1) to match input/result bit width (2)}}
    %0 = hlep.exp %theta hamiltonian<1, Z[0]> %q : (f64, !hlep.lin<i2>) -> !hlep.lin<i2>
    return %0 : !hlep.lin<i2>
}
