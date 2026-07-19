// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// Tests for the control-flow linearity check performed by
// `PrelimHLEPDialect::verifyOperationAttribute` on `prelim_hlep.halo`
// function arguments (see `checkPreciselyOneUse` in PrelimHLEPDialect.cpp).
// This is a best-effort analysis: it only ever accepts IR it can positively
// prove linear, so anything it can't fully account for is also rejected
// (see prelim-hlep-dialect-test.mlir for the cases it can prove linear).

// A halo'ed argument that is never used.
// expected-error @below {{'prelimhlep.halo' function argument #0 is subject to linearity, but is never used}}
func.func private @zero_uses(%v: !prelimhlep.linear_unit) -> !prelimhlep.linear_unit attributes { prelimhlep.halo = #prelimhlep.halo } {
    %u = prelimhlep.unit_value : !prelimhlep.linear_unit
    return %u : !prelimhlep.linear_unit
}

// -----

// A halo'ed argument used twice, unconditionally.
// expected-error @below {{'prelimhlep.halo' function argument #0 is subject to linearity, but is used more than once}}
func.func private @two_uses(%v: !prelimhlep.linear_unit) -> (!prelimhlep.linear_unit, !prelimhlep.linear_unit) attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-note @below {{used 2 times here}}
    return %v, %v : !prelimhlep.linear_unit, !prelimhlep.linear_unit
}

// -----

// scf.if where only the `then` branch uses the argument: the `else` branch
// is a control-flow path with zero uses.
// expected-error @below {{'prelimhlep.halo' function argument #1 is subject to linearity, but is not used on every control-flow path}}
func.func private @if_missing_use_in_one_arm(%cond: i1, %v: !prelimhlep.linear_unit) -> !prelimhlep.linear_unit attributes { prelimhlep.halo = #prelimhlep.halo } {
    %r = scf.if %cond -> (!prelimhlep.linear_unit) {
        // expected-note @below {{used on this control-flow path}}
        scf.yield %v : !prelimhlep.linear_unit
    } else {
        // expected-note @below {{not used on this control-flow path}}
        %u = prelimhlep.unit_value : !prelimhlep.linear_unit
        scf.yield %u : !prelimhlep.linear_unit
    }
    return %r : !prelimhlep.linear_unit
}

// -----

// scf.if where the `then` branch uses the argument twice.
// expected-error @below {{'prelimhlep.halo' function argument #1 is subject to linearity, but is used more than once on this control-flow path}}
func.func private @if_double_use_in_one_arm(%cond: i1, %v: !prelimhlep.linear_unit) -> (!prelimhlep.linear_unit, !prelimhlep.linear_unit) attributes { prelimhlep.halo = #prelimhlep.halo } {
    %r0, %r1 = scf.if %cond -> (!prelimhlep.linear_unit, !prelimhlep.linear_unit) {
        // expected-note @below {{used here}}
        // expected-note @below {{and here}}
        scf.yield %v, %v : !prelimhlep.linear_unit, !prelimhlep.linear_unit
    } else {
        %u0 = prelimhlep.unit_value : !prelimhlep.linear_unit
        %u1 = prelimhlep.unit_value : !prelimhlep.linear_unit
        scf.yield %u0, %u1 : !prelimhlep.linear_unit, !prelimhlep.linear_unit
    }
    return %r0, %r1 : !prelimhlep.linear_unit, !prelimhlep.linear_unit
}

// -----

// A halo'ed argument used inside a loop body: the analysis can't determine
// how many times the loop runs, so it rejects the IR rather than guessing.
// expected-error @below {{'prelimhlep.halo' function argument #0 is subject to linearity, but is used inside a loop, where the number of dynamic uses cannot be determined statically}}
func.func private @used_in_loop(%v: !prelimhlep.linear_unit) -> !prelimhlep.linear_unit attributes { prelimhlep.halo = #prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    %r = scf.for %i = %c0 to %c4 step %c1 iter_args(%acc = %v) -> (!prelimhlep.linear_unit) {
        // expected-note @below {{used here}}
        scf.yield %v : !prelimhlep.linear_unit
    }
    return %r : !prelimhlep.linear_unit
}
