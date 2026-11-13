// RUN: qcc-opt %s --convert-oq3-to-qref --canonicalize | FileCheck %s

module attributes {oq3.version = #oq3.version<3, 1>} {
  // CHECK-LABEL: func.func @stdgates
  func.func @stdgates() attributes {qcc.entry_point} {
    // CHECK-DAG: %[[C:.*]] = arith.constant 3.000000e-01 : f64
    // CHECK-DAG: %[[B:.*]] = arith.constant 2.000000e-01 : f64
    // CHECK-DAG: %[[A:.*]] = arith.constant 1.000000e-01 : f64
    // CHECK-DAG: %[[HALF_PI:.*]] = arith.constant 1.5707963267948966 : f64
    // CHECK-DAG: %[[Q:.*]] = qcc.alloc : !qcc.qubit_ref
    // CHECK-DAG: %[[R:.*]] = qcc.alloc : !qcc.qubit_ref
    oq3.include "stdgates.inc" id 0
    %0 = oq3.qubit_decl "q" : !qcc.qubit_ref
    %1 = oq3.qubit_decl "r" : !qcc.qubit_ref
    // Direct correspondences.
    oq3.gate_call @x [%0 : !qcc.qubit_ref]
    // CHECK:      qref.single x %[[Q]] : !qcc.qubit_ref
    oq3.gate_call @y [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single y %[[Q]] : !qcc.qubit_ref
    oq3.gate_call @z [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single z %[[Q]] : !qcc.qubit_ref
    oq3.gate_call @h [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single h %[[Q]] : !qcc.qubit_ref
    oq3.gate_call @s [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single s %[[Q]] : !qcc.qubit_ref
    oq3.gate_call @sdg [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single sdg %[[Q]] : !qcc.qubit_ref
    oq3.gate_call @t [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single t %[[Q]] : !qcc.qubit_ref
    oq3.gate_call @tdg [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single tdg %[[Q]] : !qcc.qubit_ref
    oq3.gate_call @sx [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single sx %[[Q]] : !qcc.qubit_ref
    %2 = oq3.constant #oq3.float<"0.1"> : !oq3.float
    %3 = oq3.cast %2 implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @rx(%3 : !qcc.angle) [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single rx(%[[A]]) %[[Q]] : f64, !qcc.qubit_ref
    %4 = oq3.constant #oq3.float<"0.1"> : !oq3.float
    %5 = oq3.cast %4 implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @ry(%5 : !qcc.angle) [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single ry(%[[A]]) %[[Q]] : f64, !qcc.qubit_ref
    %6 = oq3.constant #oq3.float<"0.1"> : !oq3.float
    %7 = oq3.cast %6 implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @rz(%7 : !qcc.angle) [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single rz(%[[A]]) %[[Q]] : f64, !qcc.qubit_ref
    oq3.gate_call @cx [%0, %1 : !qcc.qubit_ref, !qcc.qubit_ref]
    // CHECK-NEXT: qref.pair cx %[[Q]], %[[R]] : !qcc.qubit_ref
    oq3.gate_call @CX [%0, %1 : !qcc.qubit_ref, !qcc.qubit_ref]
    // CHECK-NEXT: qref.pair cx %[[Q]], %[[R]] : !qcc.qubit_ref
    oq3.gate_call @cy [%0, %1 : !qcc.qubit_ref, !qcc.qubit_ref]
    // CHECK-NEXT: qref.pair cy %[[Q]], %[[R]] : !qcc.qubit_ref
    oq3.gate_call @cz [%0, %1 : !qcc.qubit_ref, !qcc.qubit_ref]
    // CHECK-NEXT: qref.pair cz %[[Q]], %[[R]] : !qcc.qubit_ref
    oq3.gate_call @swap [%0, %1 : !qcc.qubit_ref, !qcc.qubit_ref]
    // CHECK-NEXT: qref.pair swap %[[Q]], %[[R]] : !qcc.qubit_ref
    %8 = oq3.constant #oq3.float<"0.1"> : !oq3.float
    %9 = oq3.cast %8 implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @cp(%9 : !qcc.angle) [%0, %1 : !qcc.qubit_ref, !qcc.qubit_ref]
    // CHECK-NEXT: qref.pair cp(%[[A]]) %[[Q]], %[[R]] : f64, !qcc.qubit_ref
    %10 = oq3.constant #oq3.float<"0.1"> : !oq3.float
    %11 = oq3.cast %10 implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @cphase(%11 : !qcc.angle) [%0, %1 : !qcc.qubit_ref, !qcc.qubit_ref]
    // CHECK-NEXT: qref.pair cp(%[[A]]) %[[Q]], %[[R]] : f64, !qcc.qubit_ref
    // Phase gates are rz up to a global phase, U is u_zyz with reordered parameters.
    %14 = oq3.constant #oq3.float<"0.1"> : !oq3.float
    %15 = oq3.cast %14 implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @p(%15 : !qcc.angle) [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single rz(%[[A]]) %[[Q]] : f64, !qcc.qubit_ref
    %16 = oq3.constant #oq3.float<"0.1"> : !oq3.float
    %17 = oq3.cast %16 implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @phase(%17 : !qcc.angle) [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single rz(%[[A]]) %[[Q]] : f64, !qcc.qubit_ref
    %18 = oq3.constant #oq3.float<"0.1"> : !oq3.float
    %19 = oq3.cast %18 implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @u1(%19 : !qcc.angle) [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single rz(%[[A]]) %[[Q]] : f64, !qcc.qubit_ref
    %20 = oq3.constant #oq3.float<"0.1"> : !oq3.float
    %21 = oq3.constant #oq3.float<"0.2"> : !oq3.float
    %22 = oq3.constant #oq3.float<"0.3"> : !oq3.float
    %23 = oq3.cast %20 implicit : !oq3.float -> !qcc.angle
    %24 = oq3.cast %21 implicit : !oq3.float -> !qcc.angle
    %25 = oq3.cast %22 implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @u3(%23, %24, %25 : !qcc.angle, !qcc.angle, !qcc.angle) [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single u_zyz(%[[C]], %[[A]], %[[B]]) %[[Q]] : f64, !qcc.qubit_ref
    %26 = oq3.constant #oq3.float<"0.1"> : !oq3.float
    %27 = oq3.constant #oq3.float<"0.2"> : !oq3.float
    %28 = oq3.constant #oq3.float<"0.3"> : !oq3.float
    %29 = oq3.cast %26 implicit : !oq3.float -> !qcc.angle
    %30 = oq3.cast %27 implicit : !oq3.float -> !qcc.angle
    %31 = oq3.cast %28 implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @U(%29, %30, %31 : !qcc.angle, !qcc.angle, !qcc.angle) [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single u_zyz(%[[C]], %[[A]], %[[B]]) %[[Q]] : f64, !qcc.qubit_ref
    %32 = oq3.constant #oq3.float<"0.1"> : !oq3.float
    %33 = oq3.constant #oq3.float<"0.2"> : !oq3.float
    %34 = oq3.cast %32 implicit : !oq3.float -> !qcc.angle
    %35 = oq3.cast %33 implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @u2(%34, %35 : !qcc.angle, !qcc.angle) [%0 : !qcc.qubit_ref]
    // CHECK-NEXT: qref.single u_zyz(%[[B]], %[[HALF_PI]], %[[A]]) %[[Q]] : f64, !qcc.qubit_ref
    oq3.gate_call @id [%0 : !qcc.qubit_ref]
    %36 = oq3.constant #oq3.float<"0.1"> : !oq3.float
    %37 = oq3.cast %36 implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @gphase(%37 : !qcc.angle)
    return
    // CHECK-NEXT: return
  }
}
