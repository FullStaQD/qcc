// RUN: qcc-opt %s --qcc-attach-device=file=%S/Inputs/device-1x2.mlir --qvec-layer --convert-qvec-to-magic --magic-shuttle-inter-trap-zz --magic-compile-swap --magic-compile-active-zz-trivially --magic-finalize-zxz --canonicalize --magic-pad-timing --magic-verify | FileCheck %s

// A Bell pair after `qvec-to-rzz` and `qvec-to-u-zxz` (h q0; cx q0, q1 = h q0; h q1; cz; h q1), compiled for a single
// trap with two ions (J = 1.0 rad/s, time unit 1 us): only native ops remain. The coupling rzz(pi/2) becomes one delay
// of (pi/2) / J s = 1570796 us, the residual Z rotations before the measurement are dropped.
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

// CHECK:      %[[C0:.*]] = magic.init : !chain
// CHECK-NEXT: %[[C1:.*]] = magic.sym_zxz %[[C0]] ions [0, 1] {x = [1.57079632679489{{[0-9]+}}, 1.57079632679489{{[0-9]+}}], z = [1.57079632679489{{[0-9]+}}, 1.57079632679489{{[0-9]+}}]} : !chain
// CHECK-NEXT: %[[C2:.*]] = magic.delay %[[C1]] {ticks = 1570796 : i64} : !chain
// CHECK-NEXT: %[[C3:.*]] = magic.sym_zxz %[[C2]] ions [1] {x = [1.57079632679489{{[0-9]+}}], z = [3.14159265358979{{[0-9]+}}]} : !chain
// CHECK-NEXT: %[[M:.*]]:2 = magic.mzd %[[C3]] : !chain -> i1, i1
// CHECK-NEXT: aux.record_int %[[M]]#0 : i1
// CHECK-NEXT: aux.record_int %[[M]]#1 : i1
// CHECK-NEXT: return
