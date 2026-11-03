// RUN: qcc-opt %s > %t
// RUN: qcc-opt %s --convert-qref-to-qcirc > %t.qcirc
// RUN: qcc-opt %s --convert-qref-to-qcirc --convert-qcirc-to-qref | diff %t -
// RUN: qcc-opt %t.qcirc --convert-qcirc-to-qref --convert-qref-to-qcirc | diff %t.qcirc -

// On qref programs of a certain shape (see comments below), qcirc -> qref inverts qref -> qcirc and vice versa.

func.func @main(%theta: f64, %cond: i1) -> i1 {
  // shape: a single `qcc.static_ref` as the very first operation.
  %q:3 = qcc.static_ref [0, 1, 2] : !qcc.qubit_ref
  qref.single h %q#0 : !qcc.qubit_ref
  qref.single rz(%theta) %q#1 : f64, !qcc.qubit_ref
  qref.pair cx %q#0, %q#1 : !qcc.qubit_ref
  qref.pair rzz(%theta) %q#1, %q#2 : f64, !qcc.qubit_ref
  %bit = qref.measure z %q#0 : !qcc.qubit_ref -> i1
  %m = scf.if %bit -> i1 {
    qref.pair cz %q#2, %q#1 : !qcc.qubit_ref
    scf.if %cond {
      qref.single x %q#2 : !qcc.qubit_ref
    }
    %m1 = qref.measure x %q#1 : !qcc.qubit_ref -> i1
    scf.yield %m1 : i1
  } else {
    scf.yield %bit : i1
  }
  qref.reset z %q#0 : !qcc.qubit_ref
  return %m : i1
}
