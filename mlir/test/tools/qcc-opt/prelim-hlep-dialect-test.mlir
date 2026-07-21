// RUN: qcc-opt %s | FileCheck %s

// Round-trip smoke test for the (stub) PrelimHLEP dialect ops/types/attrs.
// See mlir/docs/Dialects/PrelimHLEP.md for the semantics these stub out.

func.func @scale(%factor: complex<f64>, %t: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %0 = prelimhlep.scale %factor, %t : (complex<f64>, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %0 : !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func @scale
// CHECK: prelimhlep.scale

func.func @add_phase(%alpha: f64, %t: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %0 = prelimhlep.add_phase %alpha, %t : (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %0 : !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func @add_phase
// CHECK: prelimhlep.add_phase

func.func @unit_value() -> !prelimhlep.unit {
    %0 = prelimhlep.unit_value : !prelimhlep.unit
    return %0 : !prelimhlep.unit
}
// CHECK-LABEL: func.func @unit_value
// CHECK: prelimhlep.unit_value

func.func @base_change(%q: !prelimhlep.lin<i1>) -> !prelimhlep.lin<!prelimhlep.x<1>> attributes { prelimhlep.halo = #prelimhlep.halo } {
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
    %0 = prelimhlep.constant "-><-->" : !prelimhlep.lin<!prelimhlep.y<3>>
    return %0 : !prelimhlep.lin<!prelimhlep.y<3>>
}
// CHECK-LABEL: func.func @constant_y
// CHECK: prelimhlep.constant "-><-->"

func.func @exp(%theta: f64, %q: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %0 = prelimhlep.exp %theta hamiltonian<1, []> %q : (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %0 : !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func @exp
// CHECK: prelimhlep.exp

// TODO: Add test for prelimhlep.exp with actual Hamiltonian terms, once we have a way to construct them in MLIR.

func.func @lin_op(%q: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %0 = prelimhlep.lin (
        %b : i1 from %q : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i1>) {
        // TODO: cleaner syntax for auxiliary results, e.g. `prelimhlep.output (%b: i1)`.
        prelimhlep.output (%b) carrying () : [i1]
    }
    return %0 : !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func @lin_op
// CHECK: prelimhlep.lin (%{{.*}} : i1 from %{{.*}} : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>)
// CHECK: prelimhlep.output(%{{.*}}) carrying() : [i1]

func.func @lin_op_with_auxiliary_result(%q: !prelimhlep.lin<i1>) -> i1 attributes { prelimhlep.halo = #prelimhlep.halo } {
    %0 = prelimhlep.lin (
        %b : i1 from %q : !prelimhlep.lin<i1>
    ) -> (i1) {
        // TODO: cleaner syntax for auxiliary results, e.g. `prelimhlep.output () carrying (%b: i1)`.
        prelimhlep.output () carrying (%b) : , [i1]
    }
    return %0 : i1
}
// CHECK-LABEL: func.func @lin_op_with_auxiliary_result
// CHECK: prelimhlep.lin (%{{.*}} : i1 from %{{.*}} : !prelimhlep.lin<i1>) -> (i1)
// CHECK: prelimhlep.output() carrying(%{{.*}}) :, [i1]

func.func @lin_op_no_operands(%halo: !prelimhlep.unit) -> (i1, !prelimhlep.unit) attributes { prelimhlep.halo = #prelimhlep.halo } {
    %0 = prelimhlep.lin () -> (i1) {
        %v = arith.constant true
        prelimhlep.output () carrying (%v) : , [i1]
    }
    return %0, %halo : i1, !prelimhlep.unit
}
// CHECK-LABEL: func.func @lin_op_no_operands
// CHECK: prelimhlep.lin () -> (i1)
// CHECK: prelimhlep.output() carrying(%{{.*}}) :, [i1]

// The halo linearity check proves this is fine: %v is used exactly once on
// both the `then` and `else` paths of the scf.if.
func.func @halo_linearity_if_ok(%cond: i1, %v: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %r = scf.if %cond -> (!prelimhlep.lin<i1>) {
        scf.yield %v : !prelimhlep.lin<i1>
    } else {
        scf.yield %v : !prelimhlep.lin<i1>
    }
    return %r : !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func @halo_linearity_if_ok

func.func private @haloed(%halo: !prelimhlep.unit) -> !prelimhlep.unit attributes { prelimhlep.halo = #prelimhlep.halo }
// CHECK-LABEL: func.func private @haloed
// CHECK-SAME: prelimhlep.halo
