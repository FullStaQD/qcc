// RUN: qcc-opt %s -qvec-layer --split-input-file | FileCheck %s

// The rebuilt bodies were also checked numerically against the inputs (unitaries equal up to a global phase); the
// checks here pin the layer structure. Rotation angles produced by fusion may carry rounding noise, so only the
// exactly representable ones are checked to the digit.

// A Bell pair after qvec-to-rzz / qvec-to-u-zxz: h q0; h q1; rzz(pi/2); rz(-pi/2) both; h q1.
// CHECK-LABEL: func.func @bell
func.func @bell() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %pi_2 = arith.constant dense<1.5707963267948966> : vector<1xf64>
    %mpi_2 = arith.constant dense<-1.5707963267948966> : vector<1xf64>
    %a0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %b0 = vector.from_elements %q1 : vector<1x!qco.qubit>
    %a1 = qvec.single u_zxz(%pi_2, %pi_2, %pi_2) %a0 : vector<1x!qco.qubit>, vector<1xf64>
    %b1 = qvec.single u_zxz(%pi_2, %pi_2, %pi_2) %b0 : vector<1x!qco.qubit>, vector<1xf64>
    %a2, %b2 = qvec.pair rzz(%pi_2) %a1, %b1 : vector<1x!qco.qubit>, vector<1xf64>
    %a3 = qvec.single rz(%mpi_2) %a2 : vector<1x!qco.qubit>, vector<1xf64>
    %b3 = qvec.single rz(%mpi_2) %b2 : vector<1x!qco.qubit>, vector<1xf64>
    %b4 = qvec.single u_zxz(%pi_2, %pi_2, %pi_2) %b3 : vector<1x!qco.qubit>, vector<1xf64>
    %a4, %ra = qvec.mz %a3 : vector<1x!qco.qubit> -> vector<1xi1>
    %b5, %rb = qvec.mz %b4 : vector<1x!qco.qubit> -> vector<1xi1>
    %r0 = vector.extract %ra[0] : i1 from vector<1xi1>
    %r1 = vector.extract %rb[0] : i1 from vector<1xi1>
    aux.record_int %r0 : i1
    aux.record_int %r1 : i1
    func.return
}

// Fresh static qubits, one u_zxz layer over both (q0's trailing rz is folded back into it), one zz block, one u_zxz
// layer on q1 alone (rz folded in), then the measurements and the records.
// CHECK-DAG:     %[[Q0:.*]] = qco.static 0
// CHECK-DAG:     %[[Q1:.*]] = qco.static 1
// CHECK:         %[[V0:.*]] = vector.from_elements %[[Q0]], %[[Q1]] : vector<2x!qco.qubit>
// CHECK:         %[[L0:.*]] = qvec.single u_zxz(%{{.*}}, %{{.*}}, %{{.*}}) %[[V0]] : vector<2x!qco.qubit>, vector<2xf64>
// CHECK-DAG:     %[[E0:.*]] = vector.extract %[[L0]][0]
// CHECK-DAG:     %[[E1:.*]] = vector.extract %[[L0]][1]
// CHECK:         %[[V1:.*]] = vector.from_elements %[[E0]], %[[E1]] : vector<2x!qco.qubit>
// CHECK:         %[[A:.*]] = arith.constant dense<{{\[\[}}0.000000e+00, 1.5707963267948966], [1.5707963267948966, 0.000000e+00]]> : vector<2x2xf64>
// CHECK:         %[[L1:.*]] = qvec.global zz(%[[A]]) %[[V1]] : vector<2x!qco.qubit>, vector<2x2xf64>
// CHECK-DAG:     %[[F0:.*]] = vector.extract %[[L1]][0]
// CHECK-DAG:     %[[F1:.*]] = vector.extract %[[L1]][1]
// CHECK:         %[[V2:.*]] = vector.from_elements %[[F1]] : vector<1x!qco.qubit>
// CHECK:         %[[L2:.*]] = qvec.single u_zxz(%{{.*}}, %{{.*}}, %{{.*}}) %[[V2]] : vector<1x!qco.qubit>, vector<1xf64>
// CHECK:         %[[G1:.*]] = vector.extract %[[L2]][0]
// CHECK:         %[[M0:.*]] = vector.from_elements %[[F0]] : vector<1x!qco.qubit>
// CHECK:         %{{.*}}, %[[RA:.*]] = qvec.mz %[[M0]] : vector<1x!qco.qubit> -> vector<1xi1>
// CHECK:         %[[M1:.*]] = vector.from_elements %[[G1]] : vector<1x!qco.qubit>
// CHECK:         %{{.*}}, %[[RB:.*]] = qvec.mz %[[M1]] : vector<1x!qco.qubit> -> vector<1xi1>
// CHECK:         %[[R0:.*]] = vector.extract %[[RA]][0] : i1 from vector<1xi1>
// CHECK:         %[[R1:.*]] = vector.extract %[[RB]][0] : i1 from vector<1xi1>
// CHECK:         aux.record_int %[[R0]] : i1
// CHECK:         aux.record_int %[[R1]] : i1
// CHECK:         return

// -----

// CHECK-LABEL: func.func @merge_across_rz_not_across_x
func.func @merge_across_rz_not_across_x() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %q2 = qco.static 2 : !qco.qubit
    %a = arith.constant dense<0.5> : vector<1xf64>
    %b = arith.constant dense<0.25> : vector<1xf64>
    %c = arith.constant dense<0.125> : vector<1xf64>
    %zero = arith.constant dense<0.0> : vector<1xf64>
    %pi = arith.constant dense<3.1415926535897931> : vector<1xf64>
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qco.qubit>
    %v2 = vector.from_elements %q2 : vector<1x!qco.qubit>

    %v0a, %v1a = qvec.pair rzz(%a) %v0, %v1 : vector<1x!qco.qubit>, vector<1xf64>
    %v1b = qvec.single rz(%b) %v1a : vector<1x!qco.qubit>, vector<1xf64>       // diagonal: does not split the block
    %v1c, %v2c = qvec.pair rzz(%b) %v1b, %v2 : vector<1x!qco.qubit>, vector<1xf64>
    %v1d = qvec.single u_zxz(%zero, %pi, %zero) %v1c : vector<1x!qco.qubit>, vector<1xf64> // x: splits the block
    %v1e, %v2e = qvec.pair rzz(%c) %v1d, %v2c : vector<1x!qco.qubit>, vector<1xf64>
    func.return
}

// The first block couples (0,1) and (1,2), the x on q1 sits alone in between, the last rzz opens a second block over
// (1,2) only. The rz on q1 was absorbed by the x.
// CHECK-DAG:     %[[Q0:.*]] = qco.static 0
// CHECK-DAG:     %[[Q1:.*]] = qco.static 1
// CHECK-DAG:     %[[Q2:.*]] = qco.static 2
// CHECK:         %[[V0:.*]] = vector.from_elements %[[Q0]], %[[Q1]], %[[Q2]] : vector<3x!qco.qubit>
// CHECK:         %[[A0:.*]] = arith.constant dense<{{\[\[}}0.000000e+00, 5.000000e-01, 0.000000e+00], [5.000000e-01, 0.000000e+00, 2.500000e-01], [0.000000e+00, 2.500000e-01, 0.000000e+00]]> : vector<3x3xf64>
// CHECK:         %[[L0:.*]] = qvec.global zz(%[[A0]]) %[[V0]] : vector<3x!qco.qubit>, vector<3x3xf64>
// CHECK:         %[[E1:.*]] = vector.extract %[[L0]][1]
// CHECK:         %[[V1:.*]] = vector.from_elements %[[E1]] : vector<1x!qco.qubit>
// CHECK:         %[[X:.*]] = arith.constant dense<3.1415926535897931> : vector<1xf64>
// CHECK:         %[[L1:.*]] = qvec.single u_zxz(%{{.*}}, %[[X]], %{{.*}}) %[[V1]] : vector<1x!qco.qubit>, vector<1xf64>
// CHECK:         %[[F1:.*]] = vector.extract %[[L1]][0]
// CHECK:         %[[V2:.*]] = vector.from_elements %[[F1]], %{{.*}} : vector<2x!qco.qubit>
// CHECK:         %[[A1:.*]] = arith.constant dense<{{\[\[}}0.000000e+00, 1.250000e-01], [1.250000e-01, 0.000000e+00]]> : vector<2x2xf64>
// CHECK:         qvec.global zz(%[[A1]]) %[[V2]] : vector<2x!qco.qubit>, vector<2x2xf64>
// CHECK-NOT:     qvec.

// -----

// CHECK-LABEL: func.func @same_pair_adds_up
func.func @same_pair_adds_up() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %q2 = qco.static 2 : !qco.qubit
    %a = arith.constant dense<0.5> : vector<1xf64>
    %b = arith.constant dense<0.25> : vector<1xf64>
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qco.qubit>
    %v2 = vector.from_elements %q2 : vector<1x!qco.qubit>

    %v0a, %v1a = qvec.pair rzz(%a) %v0, %v1 : vector<1x!qco.qubit>, vector<1xf64>
    // A global block whose third qubit is not coupled at all: q2 does not join the layer.
    %e0 = vector.extract %v0a[0] : !qco.qubit from vector<1x!qco.qubit>
    %e1 = vector.extract %v1a[0] : !qco.qubit from vector<1x!qco.qubit>
    %e2 = vector.extract %v2[0] : !qco.qubit from vector<1x!qco.qubit>
    %w = vector.from_elements %e0, %e1, %e2 : vector<3x!qco.qubit>
    %m = arith.constant dense<[[0.0, 0.25, 0.0], [0.25, 0.0, 0.0], [0.0, 0.0, 0.0]]> : vector<3x3xf64>
    %wz = qvec.global zz(%m) %w : vector<3x!qco.qubit>, vector<3x3xf64>
    func.return
}

// CHECK:         %[[V0:.*]] = vector.from_elements %{{.*}}, %{{.*}} : vector<2x!qco.qubit>
// CHECK:         %[[A:.*]] = arith.constant dense<{{\[\[}}0.000000e+00, 7.500000e-01], [7.500000e-01, 0.000000e+00]]> : vector<2x2xf64>
// CHECK:         qvec.global zz(%[[A]]) %[[V0]] : vector<2x!qco.qubit>, vector<2x2xf64>
// CHECK-NOT:     qvec.

// -----

// CHECK-LABEL: func.func @residual_rz
func.func @residual_rz() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %a = arith.constant dense<0.5> : vector<1xf64>
    %b = arith.constant dense<0.25> : vector<1xf64>
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %v1 = vector.from_elements %q1 : vector<1x!qco.qubit>

    %v0a = qvec.single rz(%a) %v0 : vector<1x!qco.qubit>, vector<1xf64>
    %v0b, %v1b = qvec.pair rzz(%b) %v0a, %v1 : vector<1x!qco.qubit>, vector<1xf64>
    %v1c = qvec.single rz(%a) %v1b : vector<1x!qco.qubit>, vector<1xf64>
    %v1d = qvec.single rz(%a) %v1c : vector<1x!qco.qubit>, vector<1xf64>
    func.return
}

// No u_zxz anywhere, so the rz's of both qubits end up in one trailing rz layer (q1's two rz added up).
// CHECK:         qvec.global zz
// CHECK:         %[[T:.*]] = arith.constant dense<[5.000000e-01, 1.000000e+00]> : vector<2xf64>
// CHECK:         qvec.single rz(%[[T]]) %{{.*}} : vector<2x!qco.qubit>, vector<2xf64>
// CHECK-NOT:     qvec.

// -----

// A function without qvec operations is left alone, classical or not.
// CHECK-LABEL: func.func @untouched
func.func @untouched(%x: i64) -> i64 {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    func.return %y : i64
}

// CHECK:         %[[C:.*]] = arith.constant 1 : i64
// CHECK:         %[[Y:.*]] = arith.addi %arg0, %[[C]] : i64
// CHECK:         return %[[Y]]

// -----

// Classical code on the measurement results is kept in order behind the measurements, including arguments.
// CHECK-LABEL: func.func @classical_tail
func.func @classical_tail(%flag: i1) -> i1 {
    %q0 = qco.static 0 : !qco.qubit
    %pi = arith.constant dense<3.1415926535897931> : vector<1xf64>
    %zero = arith.constant dense<0.0> : vector<1xf64>
    %v0 = vector.from_elements %q0 : vector<1x!qco.qubit>
    %v1 = qvec.single u_zxz(%zero, %pi, %zero) %v0 : vector<1x!qco.qubit>, vector<1xf64>
    %v2, %bits = qvec.mz %v1 : vector<1x!qco.qubit> -> vector<1xi1>
    %bit = vector.extract %bits[0] : i1 from vector<1xi1>
    %r = arith.xori %bit, %flag : i1
    func.return %r : i1
}

// CHECK:         qvec.single u_zxz
// CHECK:         %{{.*}}, %[[BITS:.*]] = qvec.mz
// CHECK:         %[[BIT:.*]] = vector.extract %[[BITS]][0] : i1 from vector<1xi1>
// CHECK:         %[[R:.*]] = arith.xori %[[BIT]], %arg0 : i1
// CHECK:         return %[[R]]
