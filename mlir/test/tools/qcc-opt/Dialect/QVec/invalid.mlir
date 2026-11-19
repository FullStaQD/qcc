// RUN: qcc-opt %s --split-input-file --verify-diagnostics

func.func @missing_parameter() {
    %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
    %qs = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
    // expected-error @+1 {{'qvec.single' op gate 'rz' takes 1 parameter(s), got 0}}
    %rz = qvec.single rz %qs : vector<2x!qcc.qubit>
    func.return
}

// -----

func.func @too_many_parameters(%theta: vector<2xf64>) {
    %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
    %qs = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
    // expected-error @+1 {{'qvec.single' op gate 'h' takes 0 parameter(s), got 1}}
    %h = qvec.single h(%theta) %qs : vector<2xf64>, vector<2x!qcc.qubit>
    func.return
}

// -----

func.func @wrong_arity(%theta: vector<2xf64>) {
    %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
    %qs = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
    // expected-error @+1 {{'qvec.single' op gate 'u_zxz' takes 3 parameter(s), got 2}}
    %u = qvec.single u_zxz(%theta, %theta) %qs : vector<2xf64>, vector<2x!qcc.qubit>
    func.return
}

// -----

func.func @parameter_shape(%theta: vector<3xf64>) {
    %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
    %qs = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
    // expected-error @+1 {{'qvec.single' op parameter type 'vector<3xf64>' does not match the shape of the qubit vector 'vector<2x!qcc.qubit>'}}
    %rz = qvec.single rz(%theta) %qs : vector<3xf64>, vector<2x!qcc.qubit>
    func.return
}

// -----

func.func @pair_missing_parameter() {
    %q0, %q1, %q2, %q3 = qcc.static [0, 1, 2, 3] : !qcc.qubit
    %as = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
    %bs = vector.from_elements %q2, %q3 : vector<2x!qcc.qubit>
    // expected-error @+1 {{'qvec.pair' op gate 'rzz' takes 1 parameter(s), got 0}}
    %a, %b = qvec.pair rzz %as, %bs : vector<2x!qcc.qubit>
    func.return
}

// -----

func.func @pair_parameter_shape(%theta: vector<1xf64>) {
    %q0, %q1, %q2, %q3 = qcc.static [0, 1, 2, 3] : !qcc.qubit
    %as = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
    %bs = vector.from_elements %q2, %q3 : vector<2x!qcc.qubit>
    // expected-error @+1 {{'qvec.pair' op parameter type 'vector<1xf64>' does not match the shape of the qubit vector 'vector<2x!qcc.qubit>'}}
    %a, %b = qvec.pair cp(%theta) %as, %bs : vector<1xf64>, vector<2x!qcc.qubit>
    func.return
}

// -----

func.func @measure_bits_shape() {
    %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
    %qs = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
    // expected-error @+1 {{'qvec.measure' op failed to verify that all of {qubits_in, bits} have same shape}}
    %qs_out, %bits = qvec.measure z %qs : vector<2x!qcc.qubit> -> vector<3xi1>
    func.return
}
