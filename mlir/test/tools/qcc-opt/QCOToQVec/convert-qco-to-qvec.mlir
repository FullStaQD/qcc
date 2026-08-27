// RUN: qcc-opt %s -convert-qco-to-qvec --split-input-file | FileCheck %s

// The pass is a 1:1 translation using vector<1x!qco.qubit> to represent each qubit. Hence it is expected that the IR
// looks bloated. Vectorization happens in another pass and is beneficial only if program allows parallelism (the
// test cases in this file tend not to).

// CHECK-LABEL: func.func @single_gates
func.func @single_gates() {
    %q0 = qco.static 0 : !qco.qubit
    %h = qco.h %q0 : !qco.qubit -> !qco.qubit
    %x = qco.x %h : !qco.qubit -> !qco.qubit
    %y = qco.y %x : !qco.qubit -> !qco.qubit
    %z = qco.z %y : !qco.qubit -> !qco.qubit
    %s = qco.s %z : !qco.qubit -> !qco.qubit
    %sdg = qco.sdg %s : !qco.qubit -> !qco.qubit
    %t = qco.t %sdg : !qco.qubit -> !qco.qubit
    %tdg = qco.tdg %t : !qco.qubit -> !qco.qubit
    %id = qco.id %tdg : !qco.qubit -> !qco.qubit
    func.return
}

// CHECK-NOT:     qco.h
// CHECK:         %[[Q0:.*]] = qco.static 0

// CHECK:         %[[A0:.*]] = vector.from_elements %[[Q0]] : vector<1x!qco.qubit>
// CHECK:         %[[A1:.*]] = qvec.single h %[[A0]] : vector<1x!qco.qubit>
// CHECK:         %[[A2:.*]] = vector.extract %[[A1]][0] : !qco.qubit from vector<1x!qco.qubit>

// CHECK:         %[[A3:.*]] = vector.from_elements %[[A2]] : vector<1x!qco.qubit>
// CHECK:         qvec.single x %[[A3]]
// CHECK:         vector.extract

// CHECK:         qvec.single y
// CHECK:         qvec.single z
// CHECK:         qvec.single s
// CHECK:         qvec.single sdg
// CHECK:         qvec.single t
// CHECK:         qvec.single tdg
// CHECK:         qvec.single i

// -----

// CHECK-LABEL: func.func @controlled_gates
func.func @controlled_gates() {
    %c = qco.static 0 : !qco.qubit
    %t = qco.static 1 : !qco.qubit

    %cx_c, %cx_t = qco.ctrl(%c) targets(%a0 = %t) {
      %a1 = qco.x %a0 : !qco.qubit -> !qco.qubit
      qco.yield %a1
    } : ({!qco.qubit}, {!qco.qubit}) -> ({!qco.qubit}, {!qco.qubit})

    %cy_c, %cy_t = qco.ctrl(%cx_c) targets(%a0 = %cx_t) {
      %a1 = qco.y %a0 : !qco.qubit -> !qco.qubit
      qco.yield %a1
    } : ({!qco.qubit}, {!qco.qubit}) -> ({!qco.qubit}, {!qco.qubit})

    %cz_c, %cz_t = qco.ctrl(%cy_c) targets(%a0 = %cy_t) {
      %a1 = qco.z %a0 : !qco.qubit -> !qco.qubit
      qco.yield %a1
    } : ({!qco.qubit}, {!qco.qubit}) -> ({!qco.qubit}, {!qco.qubit})

    func.return
}

// Nothing of the modifier survives, region included.
// CHECK-NOT:     qco.ctrl
// CHECK-NOT:     qco.yield

// CHECK:         %[[C:.*]] = qco.static 0
// CHECK:         %[[T:.*]] = qco.static 1
// CHECK-DAG:     %[[C0:.*]] = vector.from_elements %[[C]] : vector<1x!qco.qubit>
// CHECK-DAG:     %[[T0:.*]] = vector.from_elements %[[T]] : vector<1x!qco.qubit>
// CHECK:         %[[C1:.*]], %[[T1:.*]] = qvec.pair cx %[[C0]], %[[T0]] : vector<1x!qco.qubit>
// CHECK-DAG:     %[[C2:.*]] = vector.extract %[[C1]][0] : !qco.qubit from vector<1x!qco.qubit>
// CHECK-DAG:     %[[T2:.*]] = vector.extract %[[T1]][0] : !qco.qubit from vector<1x!qco.qubit>

// CHECK:         qvec.pair cy
// CHECK:         qvec.pair cz

// -----

// CHECK-LABEL: func.func @two_qubit_gates
func.func @two_qubit_gates() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %iswap_0, %iswap_1 = qco.iswap %q0, %q1 : !qco.qubit, !qco.qubit -> !qco.qubit, !qco.qubit
    func.return
}

// CHECK-DAG:     %[[Q0:.*]] = qco.static 0
// CHECK-DAG:     %[[Q1:.*]] = qco.static 1
// CHECK-DAG:     %[[A0:.*]] = vector.from_elements %[[Q0]] : vector<1x!qco.qubit>
// CHECK-DAG:     %[[B0:.*]] = vector.from_elements %[[Q1]] : vector<1x!qco.qubit>
// CHECK:         %[[A1:.*]], %[[B1:.*]] = qvec.pair iswap %[[A0]], %[[B0]] : vector<1x!qco.qubit>
// CHECK-DAG:     %[[A2:.*]] = vector.extract %[[A1]][0] : !qco.qubit from vector<1x!qco.qubit>
// CHECK-DAG:     %[[B2:.*]] = vector.extract %[[B1]][0] : !qco.qubit from vector<1x!qco.qubit>

// -----

// CHECK-LABEL: func.func @measurement
func.func @measurement() -> i1 {
    %q0 = qco.static 0 : !qco.qubit
    %measure, %bit = qco.measure %q0 : !qco.qubit
    func.return %bit : i1
}

// CHECK:         %[[A0:.*]] = vector.from_elements %{{.*}} : vector<1x!qco.qubit>
// CHECK:         %[[A1:.*]], %[[BITS:.*]] = qvec.mz %[[A0]] : vector<1x!qco.qubit> -> vector<1xi1>
// CHECK-DAG:     %[[A2:.*]] = vector.extract %[[A1]][0] : !qco.qubit from vector<1x!qco.qubit>
// CHECK-DAG:     %[[BIT:.*]] = vector.extract %[[BITS]][0] : i1 from vector<1xi1>
// CHECK:         return %[[BIT]] : i1

// -----

// CHECK-LABEL: func.func @static_qubits_survive
func.func @static_qubits_survive() {
    %q0 = qco.static 7 : !qco.qubit
    %h = qco.h %q0 : !qco.qubit -> !qco.qubit
    func.return
}

// CHECK:         qco.static 7 : !qco.qubit
