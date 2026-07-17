// RUN: qcc-opt %s | FileCheck %s

// Round-trip smoke test for the (stub) PrelimHLEP dialect ops/types/attrs.
// See mlir/docs/Dialects/PrelimHLEP.md for the semantics these stub out.

func.func @scale(%factor: complex<f64>, %t: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> {
    %0 = prelimhlep.scale %factor, %t : (complex<f64>, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %0 : !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func @scale
// CHECK: prelimhlep.scale

func.func @add_phase(%alpha: f64, %t: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> {
    %0 = prelimhlep.add_phase %alpha, %t : (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %0 : !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func @add_phase
// CHECK: prelimhlep.add_phase

func.func @unit_value() -> !prelimhlep.linear_unit {
    %0 = prelimhlep.unit_value : !prelimhlep.linear_unit
    return %0 : !prelimhlep.linear_unit
}
// CHECK-LABEL: func.func @unit_value
// CHECK: prelimhlep.unit_value

func.func @base_change(%q: !prelimhlep.lin<i1>) -> !prelimhlep.lin<!prelimhlep.x<1>> {
    %0 = prelimhlep.base_change %q : !prelimhlep.lin<i1> -> !prelimhlep.lin<!prelimhlep.x<1>>
    return %0 : !prelimhlep.lin<!prelimhlep.x<1>>
}
// CHECK-LABEL: func.func @base_change
// CHECK: prelimhlep.base_change

func.func @constant_x() -> !prelimhlep.lin<!prelimhlep.x<3>> {
    %0 = prelimhlep.constant "++-" : !prelimhlep.lin<!prelimhlep.x<3>>
    return %0 : !prelimhlep.lin<!prelimhlep.x<3>>
}
// CHECK-LABEL: func.func @constant_x
// CHECK: prelimhlep.constant "++-"

func.func @constant_y() -> !prelimhlep.lin<!prelimhlep.y<3>> {
    %0 = prelimhlep.constant "><>" : !prelimhlep.lin<!prelimhlep.y<3>>
    return %0 : !prelimhlep.lin<!prelimhlep.y<3>>
}
// CHECK-LABEL: func.func @constant_y
// CHECK: prelimhlep.constant "><>"

func.func @exp(%theta: f64, %q: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> {
    %0 = prelimhlep.exp %theta hamiltonian<1, []> %q : (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %0 : !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func @exp
// CHECK: prelimhlep.exp

func.func @lin_op(%q: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> {
    %0 = "prelimhlep.lin"(%q) ({
    ^bb0(%b: i1):
        "prelimhlep.output"(%b) <{operandSegmentSizes = array<i32: 1, 0>}> : (i1) -> ()
    }) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %0 : !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func @lin_op
// CHECK: prelimhlep.lin

func.func @lin_op_with_auxiliary_result(%q: !prelimhlep.lin<i1>) -> i1 {
    %0 = "prelimhlep.lin"(%q) ({
    ^bb0(%b: i1):
        "prelimhlep.output"(%b) <{operandSegmentSizes = array<i32: 0, 1>}> : (i1) -> ()
    }) : (!prelimhlep.lin<i1>) -> i1
    return %0 : i1
}
// CHECK-LABEL: func.func @lin_op_with_auxiliary_result
// CHECK: prelimhlep.lin

func.func private @haloed(%halo: !prelimhlep.linear_unit) -> !prelimhlep.linear_unit attributes { prelimhlep.halo = #prelimhlep.halo }
// CHECK-LABEL: func.func private @haloed
// CHECK-SAME: prelimhlep.halo
