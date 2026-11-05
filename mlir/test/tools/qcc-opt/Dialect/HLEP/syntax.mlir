// RUN: qcc-opt %s | FileCheck %s

// Round-trip smoke test for the HLEP dialect ops/types/attrs.

func.func @add_phase(%alpha: f64, %t: !hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo = #hlep.halo } {
    %0 = hlep.add_phase %alpha, %t : (f64, !hlep.lin<i1>) -> !hlep.lin<i1>
    return %0 : !hlep.lin<i1>
}
// CHECK-LABEL: func.func @add_phase
// CHECK: hlep.add_phase

func.func @unit_value() -> !hlep.unit {
    %0 = hlep.unit_value : !hlep.unit
    return %0 : !hlep.unit
}
// CHECK-LABEL: func.func @unit_value
// CHECK: hlep.unit_value

func.func @base_change(%q: !hlep.lin<i1>) -> !hlep.lin<!hlep.x<1>> attributes { hlep.halo = #hlep.halo } {
    %0 = hlep.base_change %q : !hlep.lin<i1> -> !hlep.lin<!hlep.x<1>>
    return %0 : !hlep.lin<!hlep.x<1>>
}
// CHECK-LABEL: func.func @base_change
// CHECK: hlep.base_change

func.func @constant_x() -> !hlep.x<3> {
    %0 = hlep.constant "++-" : !hlep.x<3>
    return %0 : !hlep.x<3>
}
// CHECK-LABEL: func.func @constant_x
// CHECK: hlep.constant "++-"

func.func @constant_y() -> !hlep.y<3> {
    %0 = hlep.constant "><>" : !hlep.y<3>
    return %0 : !hlep.y<3>
}
// CHECK-LABEL: func.func @constant_y
// CHECK: hlep.constant "><>"

func.func @exp(%theta: f64, %q: !hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo = #hlep.halo } {
    %0 = hlep.exp %theta hamiltonian<1, Z[0]> %q : (f64, !hlep.lin<i1>) -> !hlep.lin<i1>
    return %0 : !hlep.lin<i1>
}
// CHECK-LABEL: func.func @exp
// CHECK: hlep.exp

func.func @exp_with_terms(%theta: f64, %q: !hlep.lin<i3>) -> !hlep.lin<i3> attributes { hlep.halo = #hlep.halo } {
    %0 = hlep.exp %theta hamiltonian<3, X[0] * Y[2] + 1.500000e+00 * Z[1]> %q : (f64, !hlep.lin<i3>) -> !hlep.lin<i3>
    return %0 : !hlep.lin<i3>
}
// CHECK-LABEL: func.func @exp_with_terms
// CHECK: hlep.exp %{{.*}} hamiltonian <3, X[0] * Y[2] + 1.500000e+00 * Z[1]> %{{.*}}

func.func @lin_op(%q: !hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo = #hlep.halo } {
    %0 = hlep.lin (
        %b : i1 from %q : !hlep.lin<i1>
    ) -> (!hlep.lin<i1>) {
        hlep.output (%b : i1)
    }
    return %0 : !hlep.lin<i1>
}
// CHECK-LABEL: func.func @lin_op
// CHECK: hlep.lin (%{{.*}} : i1 from %{{.*}} : !hlep.lin<i1>) -> (!hlep.lin<i1>)
// CHECK: hlep.output (%{{.*}} : i1)

func.func @lin_op_with_auxiliary_result(%q: !hlep.lin<i1>) -> i1 attributes { hlep.halo = #hlep.halo } {
    %0 = hlep.lin (
        %b : i1 from %q : !hlep.lin<i1>
    ) -> (i1) {
        hlep.output () carrying (%b : i1)
    }
    return %0 : i1
}
// CHECK-LABEL: func.func @lin_op_with_auxiliary_result
// CHECK: hlep.lin (%{{.*}} : i1 from %{{.*}} : !hlep.lin<i1>) -> (i1)
// CHECK: hlep.output () carrying (%{{.*}} : i1)

func.func @lin_op_no_operands(%phase: !hlep.unit) -> (i1, !hlep.unit) attributes { hlep.halo = #hlep.halo } {
    %0 = hlep.lin () -> (i1) {
        %v = arith.constant true
        hlep.output () carrying (%v : i1)
    }
    return %0, %phase : i1, !hlep.unit
}
// CHECK-LABEL: func.func @lin_op_no_operands
// CHECK: hlep.lin () -> (i1)
// CHECK: hlep.output () carrying (%{{.*}} : i1)

func.func private @haloed(%phase: !hlep.unit) -> !hlep.unit attributes { hlep.halo = #hlep.halo }
// CHECK-LABEL: func.func private @haloed
// CHECK-SAME: hlep.halo
