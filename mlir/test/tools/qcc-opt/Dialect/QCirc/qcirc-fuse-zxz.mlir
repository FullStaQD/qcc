// RUN: qcc-opt %s -qcirc-fuse-zxz --split-input-file | FileCheck %s

// CHECK-LABEL: func.func @rz_rz
func.func @rz_rz() {
    %q = qcc.static [0] : !qcc.qubit
    %a = arith.constant 0.5 : f64
    %b = arith.constant 0.25 : f64
    %r0 = qcirc.single rz(%a) %q : f64, !qcc.qubit
    %r1 = qcirc.single rz(%b) %r0 : f64, !qcc.qubit
    func.return
}

// Two rz add up and stay an rz. The old angles go with the gates.
// CHECK:         %[[Q:.*]] = qcc.static [0] : !qcc.qubit
// CHECK-NEXT:    %[[T:.*]] = arith.constant 7.500000e-01 : f64
// CHECK-NEXT:    qcirc.single rz(%[[T]]) %[[Q]] : f64, !qcc.qubit
// CHECK-NEXT:    return

// -----

// CHECK-LABEL: func.func @rz_zxz_rz
func.func @rz_zxz_rz() {
    %q = qcc.static [0] : !qcc.qubit
    %a = arith.constant 0.5 : f64
    %b = arith.constant 0.25 : f64
    %r0 = qcirc.single rz(%b) %q : f64, !qcc.qubit
    %u = qcirc.single u_zxz(%a, %a, %a) %r0 : f64, !qcc.qubit
    %r1 = qcirc.single rz(%b) %u : f64, !qcc.qubit
    func.return
}

// An rz before a u_zxz adds to z1, one after it to z2. Both are exact, and one walk fuses the whole chain.
// CHECK:         %[[Z1:.*]] = arith.constant 7.500000e-01 : f64
// CHECK-NEXT:    %[[X:.*]] = arith.constant 5.000000e-01 : f64
// CHECK-NEXT:    %[[Z2:.*]] = arith.constant 7.500000e-01 : f64
// CHECK-NEXT:    qcirc.single u_zxz(%[[Z1]], %[[X]], %[[Z2]]) %{{.*}} : f64, !qcc.qubit
// CHECK-NEXT:    return

// -----

// CHECK-LABEL: func.func @x_x_is_identity
func.func @x_x_is_identity() {
    %q = qcc.static [0] : !qcc.qubit
    %zero = arith.constant 0.0 : f64
    %pi = arith.constant 3.1415926535897931 : f64
    %x0 = qcirc.single u_zxz(%zero, %pi, %zero) %q : f64, !qcc.qubit
    %x1 = qcirc.single u_zxz(%zero, %pi, %zero) %x0 : f64, !qcc.qubit
    func.return
}

// Two u_zxz fuse through their matrices.
// CHECK:         %[[Z1:.*]] = arith.constant 0.000000e+00 : f64
// CHECK-NEXT:    %[[X:.*]] = arith.constant 0.000000e+00 : f64
// CHECK-NEXT:    %[[Z2:.*]] = arith.constant 0.000000e+00 : f64
// CHECK-NEXT:    qcirc.single u_zxz(%[[Z1]], %[[X]], %[[Z2]]) %{{.*}} : f64, !qcc.qubit
// CHECK-NEXT:    return

// -----

// CHECK-LABEL: func.func @dynamic_angle
func.func @dynamic_angle(%theta: f64) {
    %q = qcc.static [0] : !qcc.qubit
    %a = arith.constant 0.5 : f64
    %r0 = qcirc.single rz(%a) %q : f64, !qcc.qubit
    %r1 = qcirc.single rz(%theta) %r0 : f64, !qcc.qubit
    %r2 = qcirc.single rz(%a) %r1 : f64, !qcc.qubit
    func.return
}

// A gate with an angle that is not constant fuses with neither neighbour.
// CHECK:         %[[A:.*]] = arith.constant 5.000000e-01 : f64
// CHECK-NEXT:    %[[R0:.*]] = qcirc.single rz(%[[A]]) %{{.*}} : f64, !qcc.qubit
// CHECK-NEXT:    %[[R1:.*]] = qcirc.single rz(%arg0) %[[R0]] : f64, !qcc.qubit
// CHECK-NEXT:    qcirc.single rz(%[[A]]) %[[R1]] : f64, !qcc.qubit
// CHECK-NEXT:    return
