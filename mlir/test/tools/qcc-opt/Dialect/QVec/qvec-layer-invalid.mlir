// RUN: qcc-opt %s -qvec-layer --split-input-file --verify-diagnostics

func.func @dynamic_angle(%theta: vector<1xf64>) {
    %q0 = qco.static 0 : !qco.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    // expected-error @+1 {{'qvec.single' op angles must be compile-time constants}}
    %v1 = qvec.single rz(%theta) %v0 : vector<1x!qco.qubit>, vector<1xf64>
    func.return
}

// -----

func.func @wrong_single_kind() {
    %q0 = qco.static 0 : !qco.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    // expected-error @+1 {{'qvec.single' op gate 'h' is not in the layered gate set (rz, u_zxz); run qvec-to-u-zxz first}}
    %v1 = qvec.single h %v0 : vector<1x!qco.qubit>
    func.return
}

// -----

func.func @wrong_pair_kind() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qco.qubit>
    // expected-error @+1 {{'qvec.pair' op gate 'cx' is not in the layered gate set (rzz); run qvec-to-rzz first}}
    %a, %b = qvec.pair cx %v0, %v1 : vector<1x!qco.qubit>
    func.return
}

// -----

// expected-error @+1 {{'func.func' op qvec-layer expects qubits to come from `qco.static`, not from arguments}}
func.func @argument_qubits(%qs: vector<1x!qco.qubit>) {
    %theta = arith.constant dense<0.5> : vector<1xf64>
    %v1 = qvec.single rz(%theta) %qs : vector<1x!qco.qubit>, vector<1xf64>
    func.return
}

// -----

func.func private @opaque(!qco.qubit) -> !qco.qubit

func.func @opaque_op_on_qubits() {
    %q0 = qco.static 0 : !qco.qubit
    %theta = arith.constant dense<0.5> : vector<1xf64>
    // expected-error @+1 {{'func.call' op is not a `qvec` operation and qvec-layer cannot look through it}}
    %o = func.call @opaque(%q0) : (!qco.qubit) -> !qco.qubit
    %v0 = vector.from_elements %o : vector<1x!qco.qubit>
    %v1 = qvec.single rz(%theta) %v0 : vector<1x!qco.qubit>, vector<1xf64>
    func.return
}

// -----

func.func @gate_after_measurement() {
    %q0 = qco.static 0 : !qco.qubit
    %theta = arith.constant dense<0.5> : vector<1xf64>
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %v1, %bits = qvec.mz %v0 : vector<1x!qco.qubit> -> vector<1xi1>
    // expected-error @+1 {{'qvec.single' op uses qubit 0 after its measurement}}
    %v2 = qvec.single rz(%theta) %v1 : vector<1x!qco.qubit>, vector<1xf64>
    func.return
}

// -----

func.func @control_flow(%flag: i1) {
    %q0 = qco.static 0 : !qco.qubit
    %theta = arith.constant dense<0.5> : vector<1xf64>
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %v1 = qvec.single rz(%theta) %v0 : vector<1x!qco.qubit>, vector<1xf64>
    // expected-error @+1 {{'scf.if' op qvec-layer does not support control flow}}
    scf.if %flag {
      scf.yield
    }
    func.return
}
