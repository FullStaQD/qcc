// RUN: qcc-opt %s -qvec-to-u-zxz --split-input-file | FileCheck %s

// CHECK-LABEL: func.func @non_diagonal
func.func @non_diagonal(%qs: vector<2x!qcc.qubit>) -> vector<2x!qcc.qubit> {
    %h = qvec.single h %qs : vector<2x!qcc.qubit>
    %x = qvec.single x %h : vector<2x!qcc.qubit>
    %y = qvec.single y %x : vector<2x!qcc.qubit>
    %sx = qvec.single sx %y : vector<2x!qcc.qubit>
    %sxdg = qvec.single sxdg %sx : vector<2x!qcc.qubit>
    func.return %sxdg : vector<2x!qcc.qubit>
}

// The rewrite driver hoists the constants to the top and shares equal ones.
// CHECK-DAG:     %[[M:.*]] = arith.constant dense<-1.5707963267948966> : vector<2xf64>
// CHECK-DAG:     %[[PI:.*]] = arith.constant dense<3.1415926535897931> : vector<2xf64>
// CHECK-DAG:     %[[Z:.*]] = arith.constant dense<0.000000e+00> : vector<2xf64>
// CHECK-DAG:     %[[P:.*]] = arith.constant dense<1.5707963267948966> : vector<2xf64>
// h = u_zxz(pi/2, pi/2, pi/2)
// CHECK:         %[[H:.*]] = qvec.single u_zxz(%[[P]], %[[P]], %[[P]]) %arg0 : vector<2xf64>, vector<2x!qcc.qubit>
// x = u_zxz(0, pi, 0)
// CHECK:         %[[X:.*]] = qvec.single u_zxz(%[[Z]], %[[PI]], %[[Z]]) %[[H]]
// y = u_zxz(-pi/2, pi, pi/2)
// CHECK:         %[[Y:.*]] = qvec.single u_zxz(%[[M]], %[[PI]], %[[P]]) %[[X]]
// sx = u_zxz(0, pi/2, 0)
// CHECK:         %[[SX:.*]] = qvec.single u_zxz(%[[Z]], %[[P]], %[[Z]]) %[[Y]]
// sxdg = u_zxz(0, -pi/2, 0)
// CHECK:         %[[SXDG:.*]] = qvec.single u_zxz(%[[Z]], %[[M]], %[[Z]]) %[[SX]]
// CHECK:         return %[[SXDG]]

// -----

// CHECK-LABEL: func.func @diagonal
func.func @diagonal(%qs: vector<1x!qcc.qubit>) {
    %z = qvec.single z %qs : vector<1x!qcc.qubit>
    %s = qvec.single s %z : vector<1x!qcc.qubit>
    %sdg = qvec.single sdg %s : vector<1x!qcc.qubit>
    %t = qvec.single t %sdg : vector<1x!qcc.qubit>
    %tdg = qvec.single tdg %t : vector<1x!qcc.qubit>
    func.return
}

// Diagonal gates become rz, so that a scheduler sees they commute with zz couplings.
// CHECK-DAG:     %[[Z:.*]] = arith.constant dense<3.1415926535897931> : vector<1xf64>
// CHECK-DAG:     %[[S:.*]] = arith.constant dense<1.5707963267948966> : vector<1xf64>
// CHECK-DAG:     %[[SDG:.*]] = arith.constant dense<-1.5707963267948966> : vector<1xf64>
// CHECK-DAG:     %[[T:.*]] = arith.constant dense<0.78539816339744828> : vector<1xf64>
// CHECK-DAG:     %[[TDG:.*]] = arith.constant dense<-0.78539816339744828> : vector<1xf64>
// CHECK:         %[[R0:.*]] = qvec.single rz(%[[Z]]) %arg0 : vector<1xf64>, vector<1x!qcc.qubit>
// CHECK:         %[[R1:.*]] = qvec.single rz(%[[S]]) %[[R0]]
// CHECK:         %[[R2:.*]] = qvec.single rz(%[[SDG]]) %[[R1]]
// CHECK:         %[[R3:.*]] = qvec.single rz(%[[T]]) %[[R2]]
// CHECK:         qvec.single rz(%[[TDG]]) %[[R3]]
// CHECK-NOT:     qvec.single

// -----

// CHECK-LABEL: func.func @rotations
func.func @rotations(%qs: vector<1x!qcc.qubit>, %theta: vector<1xf64>) {
    %rx = qvec.single rx(%theta) %qs : vector<1xf64>, vector<1x!qcc.qubit>
    %ry = qvec.single ry(%theta) %rx : vector<1xf64>, vector<1x!qcc.qubit>
    %rz = qvec.single rz(%theta) %ry : vector<1xf64>, vector<1x!qcc.qubit>
    %u = qvec.single u_zxz(%theta, %theta, %theta) %rz : vector<1xf64>, vector<1x!qcc.qubit>
    func.return
}

// rx(t) = u_zxz(0, t, 0) and ry(t) = u_zxz(-pi/2, t, pi/2) keep the SSA angle; rz and u_zxz are untouched.
// CHECK-DAG:     %[[P:.*]] = arith.constant dense<1.5707963267948966> : vector<1xf64>
// CHECK-DAG:     %[[M:.*]] = arith.constant dense<-1.5707963267948966> : vector<1xf64>
// CHECK-DAG:     %[[Z:.*]] = arith.constant dense<0.000000e+00> : vector<1xf64>
// CHECK:         %[[RX:.*]] = qvec.single u_zxz(%[[Z]], %arg1, %[[Z]]) %arg0
// CHECK:         %[[RY:.*]] = qvec.single u_zxz(%[[M]], %arg1, %[[P]]) %[[RX]]
// CHECK:         %[[RZ:.*]] = qvec.single rz(%arg1) %[[RY]]
// CHECK:         qvec.single u_zxz(%arg1, %arg1, %arg1) %[[RZ]]

// -----

// CHECK-LABEL: func.func @u_zyz
func.func @u_zyz(%qs: vector<1x!qcc.qubit>, %theta: vector<1xf64>) {
    %a = arith.constant dense<0.5> : vector<1xf64>
    %u0 = qvec.single u_zyz(%a, %a, %a) %qs : vector<1xf64>, vector<1x!qcc.qubit>
    %u1 = qvec.single u_zyz(%theta, %theta, %theta) %u0 : vector<1xf64>, vector<1x!qcc.qubit>
    func.return
}

// u_zyz(z1, y, z2) = u_zxz(z1 - pi/2, y, z2 + pi/2): constant angles are folded, SSA angles shifted at runtime.
// CHECK-DAG:     %[[A:.*]] = arith.constant dense<5.000000e-01> : vector<1xf64>
// CHECK-DAG:     %[[Z1:.*]] = arith.constant dense<-1.0707963267948966> : vector<1xf64>
// CHECK-DAG:     %[[Z2:.*]] = arith.constant dense<2.0707963267948966> : vector<1xf64>
// CHECK-DAG:     %[[M:.*]] = arith.constant dense<-1.5707963267948966> : vector<1xf64>
// CHECK-DAG:     %[[P:.*]] = arith.constant dense<1.5707963267948966> : vector<1xf64>
// CHECK:         %[[U0:.*]] = qvec.single u_zxz(%[[Z1]], %[[A]], %[[Z2]]) %arg0
// CHECK:         %[[T1:.*]] = arith.addf %arg1, %[[M]] : vector<1xf64>
// CHECK:         %[[T2:.*]] = arith.addf %arg1, %[[P]] : vector<1xf64>
// CHECK:         qvec.single u_zxz(%[[T1]], %arg1, %[[T2]]) %[[U0]]
// CHECK-NOT:     qvec.single
