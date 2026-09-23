// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// Ops that are only legal within a `prelim_hlep.halo`-attributed function:
// scale, add_phase, lin, output, base_change. See
// PrelimHLEPDialect.cpp:verifyWithinHaloedFunction.

func.func @scale_outside_halo(%factor: complex<f64>, %t: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> {
    // expected-error @below {{expected to be nested within a 'prelimhlep.halo'-attributed function}}
    %0 = prelimhlep.scale %factor, %t : (complex<f64>, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %0 : !prelimhlep.lin<i1>
}

// -----

func.func @add_phase_outside_halo(%alpha: f64, %t: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> {
    // expected-error @below {{expected to be nested within a 'prelimhlep.halo'-attributed function}}
    %0 = prelimhlep.add_phase %alpha, %t : (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %0 : !prelimhlep.lin<i1>
}

// -----

func.func @base_change_outside_halo(%q: !prelimhlep.lin<i1>) -> !prelimhlep.lin<!prelimhlep.x<1>> {
    // expected-error @below {{expected to be nested within a 'prelimhlep.halo'-attributed function}}
    %0 = prelimhlep.base_change %q : !prelimhlep.lin<i1> -> !prelimhlep.lin<!prelimhlep.x<1>>
    return %0 : !prelimhlep.lin<!prelimhlep.x<1>>
}

// -----

func.func @lin_outside_halo(%q: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> {
    // expected-error @below {{expected to be nested within a 'prelimhlep.halo'-attributed function}}
    %0 = prelimhlep.lin (
        %b : i1 from %q : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i1>) {
        "prelimhlep.output"(%b) <{operandSegmentSizes = array<i32: 1, 0>}> : (i1) -> ()
    }
    return %0 : !prelimhlep.lin<i1>
}
