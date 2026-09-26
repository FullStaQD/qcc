// RUN: qcc-opt %s -qvec-fuse-zxz --split-input-file | FileCheck %s

// CHECK-LABEL: func.func @rz_rz
func.func @rz_rz(%qs: vector<2x!qco.qubit>) -> vector<2x!qco.qubit> {
    %a = arith.constant dense<[0.5, 0.25]> : vector<2xf64>
    %b = arith.constant dense<[0.25, -0.5]> : vector<2xf64>
    %r0 = qvec.single rz(%a) %qs : vector<2x!qco.qubit>, vector<2xf64>
    %r1 = qvec.single rz(%b) %r0 : vector<2x!qco.qubit>, vector<2xf64>
    func.return %r1 : vector<2x!qco.qubit>
}

// Two rz add up lane by lane and stay an rz.
// CHECK:         %[[T:.*]] = arith.constant dense<[7.500000e-01, -2.500000e-01]> : vector<2xf64>
// CHECK:         %[[R:.*]] = qvec.single rz(%[[T]]) %arg0 : vector<2x!qco.qubit>, vector<2xf64>
// CHECK-NOT:     qvec.single
// CHECK:         return %[[R]]

// -----

// CHECK-LABEL: func.func @x_x_is_identity
func.func @x_x_is_identity(%qs: vector<1x!qco.qubit>) {
    %zero = arith.constant dense<0.0> : vector<1xf64>
    %pi = arith.constant dense<3.1415926535897931> : vector<1xf64>
    %x0 = qvec.single u_zxz(%zero, %pi, %zero) %qs : vector<1x!qco.qubit>, vector<1xf64>
    %x1 = qvec.single u_zxz(%zero, %pi, %zero) %x0 : vector<1x!qco.qubit>, vector<1xf64>
    func.return
}

// CHECK:         %[[Z:.*]] = arith.constant dense<0.000000e+00> : vector<1xf64>
// CHECK:         qvec.single u_zxz(%[[Z]], %[[Z]], %[[Z]]) %arg0
// CHECK-NOT:     qvec.single

// -----

// CHECK-LABEL: func.func @chain_and_rz
func.func @chain_and_rz(%qs: vector<1x!qco.qubit>) {
    %zero = arith.constant dense<0.0> : vector<1xf64>
    %a = arith.constant dense<0.5> : vector<1xf64>
    %b = arith.constant dense<0.25> : vector<1xf64>
    // rx(0.5), rx(0.25), rz(0.25): three gates fuse into one u_zxz = Rz(0.25) Rx(0.75).
    %x0 = qvec.single u_zxz(%zero, %a, %zero) %qs : vector<1x!qco.qubit>, vector<1xf64>
    %x1 = qvec.single u_zxz(%zero, %b, %zero) %x0 : vector<1x!qco.qubit>, vector<1xf64>
    %r = qvec.single rz(%b) %x1 : vector<1x!qco.qubit>, vector<1xf64>
    func.return
}

// Rounding noise of the decomposition is tolerated in the check.
// CHECK-DAG:     %[[Z1:.*]] = arith.constant dense<{{[-]?0.000000e\+00|[-]?[0-9]\.[0-9]+e-1[6-9]}}> : vector<1xf64>
// CHECK-DAG:     %[[X:.*]] = arith.constant dense<{{7.500000e-01|0.7[45][0-9]+}}> : vector<1xf64>
// CHECK-DAG:     %[[Z2:.*]] = arith.constant dense<{{2.500000e-01|0.2[45][0-9]+}}> : vector<1xf64>
// CHECK:         qvec.single u_zxz(%[[Z1]], %[[X]], %[[Z2]]) %arg0
// CHECK-NOT:     qvec.single
