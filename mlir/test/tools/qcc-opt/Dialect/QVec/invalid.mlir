// RUN: qcc-opt %s --split-input-file --verify-diagnostics

func.func @missing_parameter(%qs: vector<2x!qco.qubit>) {
    // expected-error @+1 {{'qvec.single' op gate 'rz' takes 1 parameter(s), got 0}}
    %rz = qvec.single rz %qs : vector<2x!qco.qubit>
    func.return
}

// -----

func.func @too_many_parameters(%qs: vector<2x!qco.qubit>, %theta: vector<2xf64>) {
    // expected-error @+1 {{'qvec.single' op gate 'h' takes 0 parameter(s), got 1}}
    %h = qvec.single h(%theta) %qs : vector<2x!qco.qubit>, vector<2xf64>
    func.return
}

// -----

func.func @wrong_arity(%qs: vector<2x!qco.qubit>, %theta: vector<2xf64>) {
    // expected-error @+1 {{'qvec.single' op gate 'u_zxz' takes 3 parameter(s), got 2}}
    %u = qvec.single u_zxz(%theta, %theta) %qs : vector<2x!qco.qubit>, vector<2xf64>
    func.return
}

// -----

func.func @parameter_shape(%qs: vector<2x!qco.qubit>, %theta: vector<3xf64>) {
    // expected-error @+1 {{'qvec.single' op parameter type 'vector<3xf64>' does not match the shape of the qubit vector 'vector<2x!qco.qubit>'}}
    %rz = qvec.single rz(%theta) %qs : vector<2x!qco.qubit>, vector<3xf64>
    func.return
}

// -----

func.func @pair_missing_parameter(%as: vector<2x!qco.qubit>, %bs: vector<2x!qco.qubit>) {
    // expected-error @+1 {{'qvec.pair' op gate 'rzz' takes 1 parameter(s), got 0}}
    %a, %b = qvec.pair rzz %as, %bs : vector<2x!qco.qubit>
    func.return
}

// -----

func.func @pair_parameter_shape(%as: vector<2x!qco.qubit>, %bs: vector<2x!qco.qubit>, %theta: vector<1xf64>) {
    // expected-error @+1 {{'qvec.pair' op parameter type 'vector<1xf64>' does not match the shape of the qubit vector 'vector<2x!qco.qubit>'}}
    %a, %b = qvec.pair cp(%theta) %as, %bs : vector<2x!qco.qubit>, vector<1xf64>
    func.return
}

// -----

func.func @global_matrix_size(%qs: vector<2x!qco.qubit>, %angles: vector<3x3xf64>) {
    // expected-error @+1 {{'qvec.global' op angle matrix 'vector<3x3xf64>' must be 2x2 to match the qubit vector}}
    %z = qvec.global zz(%angles) %qs : vector<2x!qco.qubit>, vector<3x3xf64>
    func.return
}

// -----

func.func @global_matrix_not_square(%qs: vector<2x!qco.qubit>, %angles: vector<2x3xf64>) {
    // expected-error @+1 {{'qvec.global' op angle matrix 'vector<2x3xf64>' must be 2x2 to match the qubit vector}}
    %z = qvec.global zz(%angles) %qs : vector<2x!qco.qubit>, vector<2x3xf64>
    func.return
}

// -----

func.func @global_matrix_asymmetric(%qs: vector<2x!qco.qubit>) {
    %a = arith.constant dense<[[0.0, 1.0], [2.0, 0.0]]> : vector<2x2xf64>
    // expected-error @+1 {{'qvec.global' op angle matrix must be symmetric, entries (1, 0) and (0, 1) differ}}
    %z = qvec.global zz(%a) %qs : vector<2x!qco.qubit>, vector<2x2xf64>
    func.return
}

// -----

func.func @global_matrix_diagonal(%qs: vector<2x!qco.qubit>) {
    %a = arith.constant dense<[[0.0, 1.0], [1.0, 3.0]]> : vector<2x2xf64>
    // expected-error @+1 {{'qvec.global' op angle matrix must have a zero diagonal, entry (1, 1) is 3.000000e+00}}
    %z = qvec.global zz(%a) %qs : vector<2x!qco.qubit>, vector<2x2xf64>
    func.return
}
