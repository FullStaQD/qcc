// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// Ops that are only legal within a `hlep.halo`-attributed function.

func.func @add_phase_outside_halo(%alpha: f64, %t: !hlep.lin<i1>) -> !hlep.lin<i1> {
    // expected-error @below {{expected to be nested within a 'hlep.halo'-attributed function}}
    %0 = hlep.add_phase %alpha, %t : (f64, !hlep.lin<i1>) -> !hlep.lin<i1>
    return %0 : !hlep.lin<i1>
}

// -----

func.func @base_change_outside_halo(%q: !hlep.lin<i1>) -> !hlep.lin<!hlep.x<1>> {
    // expected-error @below {{expected to be nested within a 'hlep.halo'-attributed function}}
    %0 = hlep.base_change %q : !hlep.lin<i1> -> !hlep.lin<!hlep.x<1>>
    return %0 : !hlep.lin<!hlep.x<1>>
}

// -----

func.func @lin_outside_halo(%q: !hlep.lin<i1>) -> !hlep.lin<i1> {
    // expected-error @below {{expected to be nested within a 'hlep.halo'-attributed function}}
    %0 = hlep.lin (
        %b : i1 from %q : !hlep.lin<i1>
    ) -> (!hlep.lin<i1>) {
        "hlep.output"(%b) <{operandSegmentSizes = array<i32: 1, 0>}> : (i1) -> ()
    }
    return %0 : !hlep.lin<i1>
}
