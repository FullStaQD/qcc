// RUN: qcc-opt %s --split-input-file --verify-diagnostics

func.func @missing_parameter(%qs: vector<2x!qcc.qubit>) {
    // expected-error @+1 {{'qvec.single' op gate 'rz' takes 1 parameter(s), got 0}}
    %rz = qvec.single rz %qs : vector<2x!qcc.qubit>
    func.return
}

// -----

func.func @too_many_parameters(%qs: vector<2x!qcc.qubit>, %theta: vector<2xf64>) {
    // expected-error @+1 {{'qvec.single' op gate 'h' takes 0 parameter(s), got 1}}
    %h = qvec.single h(%theta) %qs : vector<2xf64>, vector<2x!qcc.qubit>
    func.return
}

// -----

func.func @wrong_arity(%qs: vector<2x!qcc.qubit>, %theta: vector<2xf64>) {
    // expected-error @+1 {{'qvec.single' op gate 'u_zxz' takes 3 parameter(s), got 2}}
    %u = qvec.single u_zxz(%theta, %theta) %qs : vector<2xf64>, vector<2x!qcc.qubit>
    func.return
}

// -----

func.func @parameter_shape(%qs: vector<2x!qcc.qubit>, %theta: vector<3xf64>) {
    // expected-error @+1 {{'qvec.single' op parameter type 'vector<3xf64>' does not match the shape of the qubit vector 'vector<2x!qcc.qubit>'}}
    %rz = qvec.single rz(%theta) %qs : vector<3xf64>, vector<2x!qcc.qubit>
    func.return
}

// -----

func.func @pair_missing_parameter(%as: vector<2x!qcc.qubit>, %bs: vector<2x!qcc.qubit>) {
    // expected-error @+1 {{'qvec.pair' op gate 'rzz' takes 1 parameter(s), got 0}}
    %a, %b = qvec.pair rzz %as, %bs : vector<2x!qcc.qubit>
    func.return
}

// -----

func.func @pair_parameter_shape(%as: vector<2x!qcc.qubit>, %bs: vector<2x!qcc.qubit>, %theta: vector<1xf64>) {
    // expected-error @+1 {{'qvec.pair' op parameter type 'vector<1xf64>' does not match the shape of the qubit vector 'vector<2x!qcc.qubit>'}}
    %a, %b = qvec.pair cp(%theta) %as, %bs : vector<1xf64>, vector<2x!qcc.qubit>
    func.return
}

// -----

func.func @measure_bits_shape(%qs: vector<2x!qcc.qubit>) {
    // expected-error @+1 {{'qvec.measure' op failed to verify that all of {qubits_in, bits} have same shape}}
    %qs_out, %bits = qvec.measure z %qs : vector<2x!qcc.qubit> -> vector<3xi1>
    func.return
}
