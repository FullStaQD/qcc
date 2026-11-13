// RUN: qcc-opt %s --qcc-attach-device=file=%S/Inputs/device-1x2.mlir --convert-qcirc-to-magic --magic-layer --magic-shuttle-inter-trap-zz --magic-compile-swap --magic-compile-active-zz-trivially --magic-finalize-zxz --canonicalize --magic-pad-timing --magic-verify | FileCheck %s

// A Bell pair after `qcirc-to-rzz` and `qcirc-to-u-zxz` (h q0; cx q0, q1 = h q0; h q1; cz; h q1), compiled for a
// single trap with two ions (J = 1.0 rad/s, time unit 1 us): only native ops remain. The coupling rzz(pi/2) becomes one
// delay of (pi/2) / J s = 1570796 us, the residual Z rotations before the measurement are dropped.
// CHECK-LABEL: func.func @bell
func.func @bell() {
    %q:2 = qcc.static [0, 1] : !qcc.qubit
    %pi_2 = arith.constant 1.5707963267948966 : f64
    %mpi_2 = arith.constant -1.5707963267948966 : f64
    %a1 = qcirc.single u_zxz(%pi_2, %pi_2, %pi_2) %q#0 : f64, !qcc.qubit
    %b1 = qcirc.single u_zxz(%pi_2, %pi_2, %pi_2) %q#1 : f64, !qcc.qubit
    %a2, %b2 = qcirc.pair rzz(%pi_2) %a1, %b1 : f64, !qcc.qubit
    %a3 = qcirc.single rz(%mpi_2) %a2 : f64, !qcc.qubit
    %b3 = qcirc.single rz(%mpi_2) %b2 : f64, !qcc.qubit
    %b4 = qcirc.single u_zxz(%pi_2, %pi_2, %pi_2) %b3 : f64, !qcc.qubit
    %a4, %ra = qcirc.measure z %a3 : !qcc.qubit -> i1
    %b5, %rb = qcirc.measure z %b4 : !qcc.qubit -> i1
    aux.record_int %ra : i1
    aux.record_int %rb : i1
    func.return
}

// CHECK:      %[[C0:.*]] = magic.init : !chain
// CHECK-NEXT: %[[C1:.*]] = magic.sym_zxz %[[C0]] ions [0, 1] {x = [1.57079632679489{{[0-9]+}}, 1.57079632679489{{[0-9]+}}], z = [1.57079632679489{{[0-9]+}}, 1.57079632679489{{[0-9]+}}]} : !chain
// CHECK-NEXT: %[[C2:.*]] = magic.delay %[[C1]] {ticks = 1570796 : i64} : !chain
// CHECK-NEXT: %[[C3:.*]] = magic.sym_zxz %[[C2]] ions [1] {x = [1.57079632679489{{[0-9]+}}], z = [3.14159265358979{{[0-9]+}}]} : !chain
// CHECK-NEXT: %[[M:.*]]:2 = magic.mzd %[[C3]] : !chain -> i1, i1
// CHECK-NEXT: aux.record_int %[[M]]#0 : i1
// CHECK-NEXT: aux.record_int %[[M]]#1 : i1
// CHECK-NEXT: return
