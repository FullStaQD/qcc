// RUN: qcc-opt %s -qvec-layer --split-input-file --verify-diagnostics

// Every case below is well-formed IR that `qvec-layer` declines to handle.

func.func @dynamic_angle(%theta: vector<1xf64>) {
    %q0 = qcc.static [0] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    // expected-error @+1 {{'qvec.single' op angles must be compile-time constants}}
    %v1 = qvec.single rz(%theta) %v0 : vector<1xf64>, vector<1x!qcc.qubit>
    func.return
}

// -----

func.func @wrong_single_kind() {
    %q0 = qcc.static [0] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    // expected-error @+1 {{'qvec.single' op gate 'h' is not in the layered gate set (rz, u_zxz); run qvec-to-u-zxz first}}
    %v1 = qvec.single h %v0 : vector<1x!qcc.qubit>
    func.return
}

// -----

func.func @wrong_pair_kind() {
    %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qcc.qubit>
    // expected-error @+1 {{'qvec.pair' op gate 'cx' is not in the layered gate set (rzz); run qvec-to-rzz first}}
    %a, %b = qvec.pair cx %v0, %v1 : vector<1x!qcc.qubit>
    func.return
}

// -----

func.func @measure_x() {
    %q0 = qcc.static [0] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    // expected-error @+1 {{'qvec.measure' op measures in basis 'x', which qvec-layer does not support}}
    %v1, %bits = qvec.measure x %v0 : vector<1x!qcc.qubit> -> vector<1xi1>
    func.return
}

// -----

func.func @reset() {
    %q0 = qcc.static [0] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    // expected-error @+1 {{'qvec.reset' op is not supported by qvec-layer}}
    %v1 = qvec.reset z %v0 : vector<1x!qcc.qubit>
    func.return
}

// -----

// expected-error @+1 {{'func.func' op qvec-layer expects qubits to come from `qcc.static`, not from arguments}}
func.func @argument_qubits(%qs: vector<1x!qcc.qubit>) {
    %theta = arith.constant dense<0.5> : vector<1xf64>
    %v1 = qvec.single rz(%theta) %qs : vector<1xf64>, vector<1x!qcc.qubit>
    func.return
}

// -----

func.func private @opaque(!qcc.qubit) -> !qcc.qubit

func.func @opaque_op_on_qubits() {
    %q0 = qcc.static [0] : !qcc.qubit
    %theta = arith.constant dense<0.5> : vector<1xf64>
    // expected-error @+1 {{'func.call' op is not a `qvec` operation and qvec-layer cannot look through it}}
    %o = func.call @opaque(%q0) : (!qcc.qubit) -> !qcc.qubit
    %v0 = vector.from_elements %o : vector<1x!qcc.qubit>
    %v1 = qvec.single rz(%theta) %v0 : vector<1xf64>, vector<1x!qcc.qubit>
    func.return
}

// -----

func.func @gate_after_measurement() {
    %q0 = qcc.static [0] : !qcc.qubit
    %theta = arith.constant dense<0.5> : vector<1xf64>
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %v1, %bits = qvec.measure z %v0 : vector<1x!qcc.qubit> -> vector<1xi1>
    // expected-error @+1 {{'qvec.single' op uses qubit 0 after its measurement}}
    %v2 = qvec.single rz(%theta) %v1 : vector<1xf64>, vector<1x!qcc.qubit>
    func.return
}

// -----

func.func @acts_twice_on_qubit() {
    %q0 = qcc.static [0] : !qcc.qubit
    %theta = arith.constant dense<0.5> : vector<1xf64>
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    // expected-error @+1 {{'qvec.pair' op acts twice on qubit 0}}
    %a, %b = qvec.pair rzz(%theta) %v0, %v0 : vector<1xf64>, vector<1x!qcc.qubit>
    func.return
}

// -----

func.func @control_flow(%flag: i1) {
    %q0 = qcc.static [0] : !qcc.qubit
    %theta = arith.constant dense<0.5> : vector<1xf64>
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %v1 = qvec.single rz(%theta) %v0 : vector<1xf64>, vector<1x!qcc.qubit>
    // expected-error @+1 {{'scf.if' op qvec-layer does not support control flow}}
    scf.if %flag {
      scf.yield
    }
    func.return
}

// -----

// A `qcc.static` cannot sit in a function with several blocks, so the qubits come from an argument here.
// expected-error @+1 {{'func.func' op qvec-layer expects a single-block function}}
func.func @multi_block(%v0: vector<1x!qcc.qubit>) {
    %theta = arith.constant dense<0.5> : vector<1xf64>
    %v1 = qvec.single rz(%theta) %v0 : vector<1xf64>, vector<1x!qcc.qubit>
    cf.br ^exit
  ^exit:
    func.return
}
