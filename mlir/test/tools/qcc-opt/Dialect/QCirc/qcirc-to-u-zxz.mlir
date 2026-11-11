// RUN: qcc-opt %s -qcirc-to-u-zxz --split-input-file | FileCheck %s

// CHECK-LABEL: func.func @non_diagonal
func.func @non_diagonal() {
    %q = qcc.static [0] : !qcc.qubit
    %h = qcirc.single h %q : !qcc.qubit
    %x = qcirc.single x %h : !qcc.qubit
    %y = qcirc.single y %x : !qcc.qubit
    %sx = qcirc.single sx %y : !qcc.qubit
    %sxdg = qcirc.single sxdg %sx : !qcc.qubit
    func.return
}

// h = u_zxz(pi/2, pi/2, pi/2)
// CHECK:         %[[Q:.*]] = qcc.static [0] : !qcc.qubit
// CHECK:         %[[P:.*]] = arith.constant 1.5707963267948966 : f64
// CHECK:         %[[H:.*]] = qcirc.single u_zxz(%[[P]], %[[P]], %[[P]]) %[[Q]] : f64, !qcc.qubit
// x = u_zxz(0, pi, 0)
// CHECK:         %[[PI:.*]] = arith.constant 3.1415926535897931 : f64
// CHECK:         %[[Z:.*]] = arith.constant 0.000000e+00 : f64
// CHECK:         %[[X:.*]] = qcirc.single u_zxz(%[[Z]], %[[PI]], %[[Z]]) %[[H]]
// y = u_zxz(-pi/2, pi, pi/2)
// CHECK:         %[[M:.*]] = arith.constant -1.5707963267948966 : f64
// CHECK:         %[[PI:.*]] = arith.constant 3.1415926535897931 : f64
// CHECK:         %[[P:.*]] = arith.constant 1.5707963267948966 : f64
// CHECK:         %[[Y:.*]] = qcirc.single u_zxz(%[[M]], %[[PI]], %[[P]]) %[[X]]
// sx = u_zxz(0, pi/2, 0)
// CHECK:         %[[P:.*]] = arith.constant 1.5707963267948966 : f64
// CHECK:         %[[Z:.*]] = arith.constant 0.000000e+00 : f64
// CHECK:         %[[SX:.*]] = qcirc.single u_zxz(%[[Z]], %[[P]], %[[Z]]) %[[Y]]
// sxdg = u_zxz(0, -pi/2, 0)
// CHECK:         %[[M:.*]] = arith.constant -1.5707963267948966 : f64
// CHECK:         %[[Z:.*]] = arith.constant 0.000000e+00 : f64
// CHECK:         qcirc.single u_zxz(%[[Z]], %[[M]], %[[Z]]) %[[SX]]

// -----

// CHECK-LABEL: func.func @diagonal
func.func @diagonal() {
    %q = qcc.static [0] : !qcc.qubit
    %z = qcirc.single z %q : !qcc.qubit
    %s = qcirc.single s %z : !qcc.qubit
    %sdg = qcirc.single sdg %s : !qcc.qubit
    %t = qcirc.single t %sdg : !qcc.qubit
    %tdg = qcirc.single tdg %t : !qcc.qubit
    func.return
}

// Diagonal gates become rz, so that a scheduler sees they commute with zz couplings.
// CHECK:         %[[Z:.*]] = arith.constant 3.1415926535897931 : f64
// CHECK:         %[[R0:.*]] = qcirc.single rz(%[[Z]]) %{{.*}} : f64, !qcc.qubit
// CHECK:         %[[S:.*]] = arith.constant 1.5707963267948966 : f64
// CHECK:         %[[R1:.*]] = qcirc.single rz(%[[S]]) %[[R0]]
// CHECK:         %[[SDG:.*]] = arith.constant -1.5707963267948966 : f64
// CHECK:         %[[R2:.*]] = qcirc.single rz(%[[SDG]]) %[[R1]]
// CHECK:         %[[T:.*]] = arith.constant 0.78539816339744828 : f64
// CHECK:         %[[R3:.*]] = qcirc.single rz(%[[T]]) %[[R2]]
// CHECK:         %[[TDG:.*]] = arith.constant -0.78539816339744828 : f64
// CHECK:         qcirc.single rz(%[[TDG]]) %[[R3]]
// CHECK-NOT:     qcirc.single

// -----

// CHECK-LABEL: func.func @rotations
func.func @rotations(%theta: f64) {
    %q = qcc.static [0] : !qcc.qubit
    %rx = qcirc.single rx(%theta) %q : f64, !qcc.qubit
    %ry = qcirc.single ry(%theta) %rx : f64, !qcc.qubit
    %rz = qcirc.single rz(%theta) %ry : f64, !qcc.qubit
    %u = qcirc.single u_zxz(%theta, %theta, %theta) %rz : f64, !qcc.qubit
    func.return
}

// rx(t) = u_zxz(0, t, 0) and ry(t) = u_zxz(-pi/2, t, pi/2) keep the SSA angle; rz and u_zxz are untouched.
// CHECK:         %[[Z:.*]] = arith.constant 0.000000e+00 : f64
// CHECK:         %[[RX:.*]] = qcirc.single u_zxz(%[[Z]], %arg0, %[[Z]]) %{{.*}}
// CHECK:         %[[M:.*]] = arith.constant -1.5707963267948966 : f64
// CHECK:         %[[P:.*]] = arith.constant 1.5707963267948966 : f64
// CHECK:         %[[RY:.*]] = qcirc.single u_zxz(%[[M]], %arg0, %[[P]]) %[[RX]]
// CHECK:         %[[RZ:.*]] = qcirc.single rz(%arg0) %[[RY]]
// CHECK:         qcirc.single u_zxz(%arg0, %arg0, %arg0) %[[RZ]]

// -----

// CHECK-LABEL: func.func @u_zyz
func.func @u_zyz(%theta: f64) {
    %q = qcc.static [0] : !qcc.qubit
    %a = arith.constant 0.5 : f64
    %u0 = qcirc.single u_zyz(%a, %a, %a) %q : f64, !qcc.qubit
    %u1 = qcirc.single u_zyz(%theta, %theta, %theta) %u0 : f64, !qcc.qubit
    func.return
}

// u_zyz(z1, y, z2) = u_zxz(z1 - pi/2, y, z2 + pi/2): constant angles are folded, SSA angles shifted at runtime.
// CHECK:         %[[A:.*]] = arith.constant 5.000000e-01 : f64
// CHECK:         %[[Z1:.*]] = arith.constant -1.0707963267948966 : f64
// CHECK:         %[[Z2:.*]] = arith.constant 2.0707963267948966 : f64
// CHECK:         %[[U0:.*]] = qcirc.single u_zxz(%[[Z1]], %[[A]], %[[Z2]]) %{{.*}}
// CHECK:         %[[M:.*]] = arith.constant -1.5707963267948966 : f64
// CHECK:         %[[T1:.*]] = arith.addf %arg0, %[[M]] : f64
// CHECK:         %[[P:.*]] = arith.constant 1.5707963267948966 : f64
// CHECK:         %[[T2:.*]] = arith.addf %arg0, %[[P]] : f64
// CHECK:         qcirc.single u_zxz(%[[T1]], %arg0, %[[T2]]) %[[U0]]
// CHECK-NOT:     qcirc.single
