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

// CHECK-LABEL: func.func @zxz_zxz
func.func @zxz_zxz() {
    %q = qcc.static [0] : !qcc.qubit
    %a = arith.constant 0.5 : f64
    %b = arith.constant 0.25 : f64
    %u0 = qcirc.single u_zxz(%a, %b, %a) %q : f64, !qcc.qubit
    %u1 = qcirc.single u_zxz(%b, %a, %b) %u0 : f64, !qcc.qubit
    func.return
}

// Two u_zxz fuse through their matrices into one with new constant angles. The old angles go with the gates.
// CHECK:         %[[Q:.*]] = qcc.static [0] : !qcc.qubit
// CHECK-NEXT:    %[[Z1:.*]] = arith.constant {{.*}} : f64
// CHECK-NEXT:    %[[X:.*]] = arith.constant {{.*}} : f64
// CHECK-NEXT:    %[[Z2:.*]] = arith.constant {{.*}} : f64
// CHECK-NEXT:    qcirc.single u_zxz(%[[Z1]], %[[X]], %[[Z2]]) %[[Q]] : f64, !qcc.qubit
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
