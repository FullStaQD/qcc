// RUN: qcc-opt %s --convert-qc-to-qref --convert-qref-to-qcirc | FileCheck %s

// From `qc` to `qcirc` through `qref`. The input is the output of the Qrisp lowering for
// `qrisp-integration/qir/t_gate_teleportation.py`.

// CHECK-LABEL: func.func public @main
func.func public @main() -> i1 attributes {qcc.entry_point} {
  %0 = qc.static 0 : !qc.qubit
  %1 = qc.static 1 : !qc.qubit
  qc.h %1 : !qc.qubit
  qc.h %0 : !qc.qubit
  qc.t %0 : !qc.qubit
  qc.ctrl(%1) targets (%arg0 = %0) {
    qc.x %arg0 : !qc.qubit
    qc.yield
  } : {!qc.qubit}, {!qc.qubit}
  %2 = qc.measure %0 : !qc.qubit -> i1
  scf.if %2 {
    qc.s %1 : !qc.qubit
  }
  qc.tdg %1 : !qc.qubit
  qc.h %1 : !qc.qubit
  %3 = qc.measure %1 : !qc.qubit -> i1
  return %3 : i1
}
// CHECK:         %[[Q:.*]]:2 = qcc.static [0, 1] : !qcc.qubit
// CHECK-NEXT:    %[[H1:.*]] = qcirc.single h %[[Q]]#1 : !qcc.qubit
// CHECK-NEXT:    %[[H0:.*]] = qcirc.single h %[[Q]]#0 : !qcc.qubit
// CHECK-NEXT:    %[[T0:.*]] = qcirc.single t %[[H0]] : !qcc.qubit
// CHECK-NEXT:    %[[C1:.*]], %[[C0:.*]] = qcirc.pair cx %[[H1]], %[[T0]] : !qcc.qubit
// CHECK-NEXT:    %{{.*}}, %[[BIT:.*]] = qcirc.measure z %[[C0]] : !qcc.qubit -> i1
// CHECK-NEXT:    %[[IF:.*]] = qcf.if %[[BIT]] (%[[A:.*]] = %[[C1]]) -> !qcc.qubit {
// CHECK-NEXT:      %[[S:.*]] = qcirc.single s %[[A]] : !qcc.qubit
// CHECK-NEXT:      qcf.yield %[[S]] : !qcc.qubit
// CHECK-NEXT:    }
// CHECK-NEXT:    %[[TDG:.*]] = qcirc.single tdg %[[IF]] : !qcc.qubit
// CHECK-NEXT:    %[[H:.*]] = qcirc.single h %[[TDG]] : !qcc.qubit
// CHECK-NEXT:    %{{.*}}, %[[M:.*]] = qcirc.measure z %[[H]] : !qcc.qubit -> i1
// CHECK-NEXT:    return %[[M]] : i1
