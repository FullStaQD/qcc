// RUN: qcc-opt %s -qcirc-to-rzz --split-input-file | FileCheck %s

// CHECK-LABEL: func.func @cz
func.func @cz() {
    %q:2 = qcc.static [0, 1] : !qcc.qubit
    %a, %b = qcirc.pair cz %q#0, %q#1 : !qcc.qubit
    func.return
}

// cz = (rz(-pi/2) (x) rz(-pi/2)) * rzz(pi/2)
// CHECK:         %[[Q:.*]]:2 = qcc.static [0, 1] : !qcc.qubit
// CHECK:         %[[P:.*]] = arith.constant 1.5707963267948966 : f64
// CHECK:         %[[A:.*]], %[[B:.*]] = qcirc.pair rzz(%[[P]]) %[[Q]]#0, %[[Q]]#1 : f64, !qcc.qubit
// CHECK:         %[[M:.*]] = arith.constant -1.5707963267948966 : f64
// CHECK:         qcirc.single rz(%[[M]]) %[[A]] : f64, !qcc.qubit
// CHECK:         qcirc.single rz(%[[M]]) %[[B]] : f64, !qcc.qubit
// CHECK-NOT:     qcirc.

// -----

// CHECK-LABEL: func.func @cx
func.func @cx() {
    %q:2 = qcc.static [0, 1] : !qcc.qubit
    %c, %t = qcirc.pair cx %q#0, %q#1 : !qcc.qubit
    func.return
}

// cx = h_t * cz * h_t; the target is the right operand.
// CHECK:         %[[Q:.*]]:2 = qcc.static [0, 1] : !qcc.qubit
// CHECK:         %[[T0:.*]] = qcirc.single h %[[Q]]#1 : !qcc.qubit
// CHECK:         %[[C1:.*]], %[[T1:.*]] = qcirc.pair rzz(%{{.*}}) %[[Q]]#0, %[[T0]]
// CHECK:         qcirc.single rz(%{{.*}}) %[[C1]]
// CHECK:         %[[T2:.*]] = qcirc.single rz(%{{.*}}) %[[T1]]
// CHECK:         qcirc.single h %[[T2]]
// CHECK-NOT:     qcirc.

// -----

// CHECK-LABEL: func.func @cy
func.func @cy() {
    %q:2 = qcc.static [0, 1] : !qcc.qubit
    %c, %t = qcirc.pair cy %q#0, %q#1 : !qcc.qubit
    func.return
}

// cy = s_t * cx * sdg_t
// CHECK:         %[[T0:.*]] = qcirc.single sdg %{{.*}}#1 : !qcc.qubit
// CHECK:         %[[T1:.*]] = qcirc.single h %[[T0]]
// CHECK:         %[[C2:.*]], %[[T2:.*]] = qcirc.pair rzz(%{{.*}}) %{{.*}}, %[[T1]]
// CHECK:         qcirc.single rz(%{{.*}}) %[[C2]]
// CHECK:         %[[T3:.*]] = qcirc.single rz(%{{.*}}) %[[T2]]
// CHECK:         %[[T4:.*]] = qcirc.single h %[[T3]]
// CHECK:         qcirc.single s %[[T4]]
// CHECK-NOT:     qcirc.

// -----

// CHECK-LABEL: func.func @cp_constant
func.func @cp_constant() {
    %q:2 = qcc.static [0, 1] : !qcc.qubit
    %theta = arith.constant 0.5 : f64
    %a, %b = qcirc.pair cp(%theta) %q#0, %q#1 : f64, !qcc.qubit
    func.return
}

// cp(t) = (rz(t/2) (x) rz(t/2)) * rzz(-t/2), folded.
// CHECK:         %[[MH:.*]] = arith.constant -2.500000e-01 : f64
// CHECK:         %[[A:.*]], %[[B:.*]] = qcirc.pair rzz(%[[MH]]) %{{.*}}, %{{.*}} : f64, !qcc.qubit
// CHECK:         %[[H:.*]] = arith.constant 2.500000e-01 : f64
// CHECK:         qcirc.single rz(%[[H]]) %[[A]]
// CHECK:         qcirc.single rz(%[[H]]) %[[B]]

// -----

// CHECK-LABEL: func.func @cp_dynamic
func.func @cp_dynamic(%theta: f64) {
    %q:2 = qcc.static [0, 1] : !qcc.qubit
    %a, %b = qcirc.pair cp(%theta) %q#0, %q#1 : f64, !qcc.qubit
    func.return
}

// An SSA angle is scaled at runtime.
// CHECK:         %[[MHC:.*]] = arith.constant -5.000000e-01 : f64
// CHECK:         %[[MH:.*]] = arith.mulf %arg0, %[[MHC]] : f64
// CHECK:         %[[A:.*]], %[[B:.*]] = qcirc.pair rzz(%[[MH]])
// CHECK:         %[[HC:.*]] = arith.constant 5.000000e-01 : f64
// CHECK:         %[[H:.*]] = arith.mulf %arg0, %[[HC]] : f64
// CHECK:         qcirc.single rz(%[[H]]) %[[A]]
// CHECK:         qcirc.single rz(%[[H]]) %[[B]]

// -----

// CHECK-LABEL: func.func @crz
func.func @crz() {
    %q:2 = qcc.static [0, 1] : !qcc.qubit
    %theta = arith.constant 0.5 : f64
    %c, %t = qcirc.pair crz(%theta) %q#0, %q#1 : f64, !qcc.qubit
    func.return
}

// crz(t) = (1 (x) rz(t/2)) * rzz(-t/2): unlike cp, only the target gets an rz.
// CHECK:         %[[MH:.*]] = arith.constant -2.500000e-01 : f64
// CHECK:         %[[C:.*]], %[[T:.*]] = qcirc.pair rzz(%[[MH]]) %{{.*}}#0, %{{.*}}#1 : f64, !qcc.qubit
// CHECK:         %[[H:.*]] = arith.constant 2.500000e-01 : f64
// CHECK:         qcirc.single rz(%[[H]]) %[[T]]
// CHECK-NOT:     qcirc.

// -----

// CHECK-LABEL: func.func @rxx
func.func @rxx(%theta: f64) {
    %q:2 = qcc.static [0, 1] : !qcc.qubit
    %a, %b = qcirc.pair rxx(%theta) %q#0, %q#1 : f64, !qcc.qubit
    func.return
}

// rxx(t) = (h (x) h) * rzz(t) * (h (x) h)
// CHECK:         %[[A0:.*]] = qcirc.single h %{{.*}}#0 : !qcc.qubit
// CHECK:         %[[B0:.*]] = qcirc.single h %{{.*}}#1 : !qcc.qubit
// CHECK:         %[[A1:.*]], %[[B1:.*]] = qcirc.pair rzz(%arg0) %[[A0]], %[[B0]] : f64, !qcc.qubit
// CHECK:         qcirc.single h %[[A1]]
// CHECK:         qcirc.single h %[[B1]]

// -----

// CHECK-LABEL: func.func @ryy
func.func @ryy(%theta: f64) {
    %q:2 = qcc.static [0, 1] : !qcc.qubit
    %a, %b = qcirc.pair ryy(%theta) %q#0, %q#1 : f64, !qcc.qubit
    func.return
}

// ryy(t) = (rx(-pi/2) (x) rx(-pi/2)) * rzz(t) * (rx(pi/2) (x) rx(pi/2))
// CHECK:         %[[P:.*]] = arith.constant 1.5707963267948966 : f64
// CHECK:         %[[A0:.*]] = qcirc.single rx(%[[P]]) %{{.*}}#0
// CHECK:         %[[B0:.*]] = qcirc.single rx(%[[P]]) %{{.*}}#1
// CHECK:         %[[A1:.*]], %[[B1:.*]] = qcirc.pair rzz(%arg0) %[[A0]], %[[B0]]
// CHECK:         %[[M:.*]] = arith.constant -1.5707963267948966 : f64
// CHECK:         qcirc.single rx(%[[M]]) %[[A1]]
// CHECK:         qcirc.single rx(%[[M]]) %[[B1]]

// -----

// CHECK-LABEL: func.func @swap
func.func @swap() {
    %q:2 = qcc.static [0, 1] : !qcc.qubit
    %a, %b = qcirc.pair swap %q#0, %q#1 : !qcc.qubit
    func.return
}

// swap = cx(a, b) * cx(b, a) * cx(a, b): three rzz in total, no other pair gate left.
// CHECK-COUNT-3: qcirc.pair rzz
// CHECK-NOT:     qcirc.pair

// -----

// CHECK-LABEL: func.func @iswap
func.func @iswap() {
    %q:2 = qcc.static [0, 1] : !qcc.qubit
    %a, %b = qcirc.pair iswap %q#0, %q#1 : !qcc.qubit
    func.return
}

// iswap = swap * cz * (s (x) s), swap = three cx: four rzz in total, no other pair gate left.
// CHECK:         qcirc.single s
// CHECK:         qcirc.single s
// CHECK-COUNT-4: qcirc.pair rzz
// CHECK-NOT:     qcirc.pair

// -----

// CHECK-LABEL: func.func @rzz_stays
func.func @rzz_stays(%theta: f64) {
    %q:2 = qcc.static [0, 1] : !qcc.qubit
    %a, %b = qcirc.pair rzz(%theta) %q#0, %q#1 : f64, !qcc.qubit
    func.return
}

// CHECK:         qcirc.pair rzz(%arg0) %{{.*}}#0, %{{.*}}#1
// CHECK-NOT:     qcirc.
