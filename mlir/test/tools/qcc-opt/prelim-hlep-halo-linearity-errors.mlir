// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// Tests for the control-flow linearity check performed by
// `PrelimHLEPDialect::verifyOperationAttribute` on `prelim_hlep.halo`
// function arguments (see `checkPreciselyOneUse` in PrelimHLEPDialect.cpp).
// This is a best-effort analysis: it only ever accepts IR it can positively
// prove linear, so anything it can't fully account for is also rejected
// (see prelim-hlep-dialect-test.mlir for the cases it can prove linear).
// Each diagnostic is anchored at whichever op is most relevant to the
// specific failure (the defining op for a zero-use error, an offending use
// for a double-use error, the responsible branch op for a coverage-gap
// error, ...), not uniformly at the enclosing function.

func.func private @make_qubit() -> !prelimhlep.lin<i1>

// A halo'ed argument that is never used: the error is anchored at the
// function itself, since that's what "defines" a function argument.
// expected-error @below {{'prelimhlep.halo' function argument #0 is subject to linearity, but is never used}}
func.func private @zero_uses(%v: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %u = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
    return %u : !prelimhlep.lin<i1>
}

// -----

// A halo'ed argument used twice, unconditionally: the error is anchored at
// one of the offending uses (here, the only op that uses it).
func.func private @two_uses(%v: !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{'prelimhlep.halo' function argument #0 is subject to linearity, but is used more than once}}
    // expected-note @below {{used 2 times here}}
    return %v, %v : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !prelimhlep.lin<i1>

// A halo'ed value used twice, unconditionally: the error is anchored at one
// of the offending uses, not at the value's defining op.
func.func private @two_uses_locally_defined(%1: !prelimhlep.unit) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo = #prelimhlep.halo } {
    %v = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
    // expected-error @below {{'prelimhlep.halo' result #0 of 'func.call' is subject to linearity, but is used more than once}}
    // expected-note @below {{used 2 times here}}
    return %v, %v : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !prelimhlep.lin<i1>

// scf.if where only the `then` branch uses the argument: the `else` branch
// is a control-flow path with zero uses. The error is anchored at the
// `scf.if` itself, the construct responsible for the uncovered path.
func.func private @if_missing_use_in_one_arm(%cond: i1, %v: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{'prelimhlep.halo' function argument #1 is subject to linearity, but is not used on every control-flow path}}
    %r = scf.if %cond -> (!prelimhlep.lin<i1>) {
        // expected-note @below {{used on this control-flow path}}
        scf.yield %v : !prelimhlep.lin<i1>
    } else {
        // expected-note @below {{not used on this control-flow path}}
        %u = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
        scf.yield %u : !prelimhlep.lin<i1>
    }
    return %r : !prelimhlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !prelimhlep.lin<i1>

// scf.if where the `then` branch uses the argument twice: the error is
// anchored at the offending use, inside that arm.
func.func private @if_double_use_in_one_arm(%cond: i1, %v: !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo = #prelimhlep.halo } {
    %r0, %r1 = scf.if %cond -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        // expected-error @below {{'prelimhlep.halo' function argument #1 is subject to linearity, but is used more than once on this control-flow path}}
        // expected-note @below {{used 2 times here}}
        scf.yield %v, %v : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
    } else {
        %u0 = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
        %u1 = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
        scf.yield %u0, %u1 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
    }
    return %r0, %r1 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !prelimhlep.lin<i1>

// Nested scf.if: the outer `else` uses the argument, and the outer `then`
// contains a nested scf.if -- but that nested if's `else` arm does not use
// it, so this control-flow path (outer `then`, inner `else`) has zero uses.
// The error is anchored at the inner `scf.if`, the construct actually
// responsible for the uncovered path.
func.func private @nested_if_missing_use_in_inner_arm(%cond0: i1, %cond1: i1, %v: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %r = scf.if %cond0 -> (!prelimhlep.lin<i1>) {
        // expected-error @below {{'prelimhlep.halo' function argument #2 is subject to linearity, but is not used on every control-flow path}}
        %inner = scf.if %cond1 -> (!prelimhlep.lin<i1>) {
            // expected-note @below {{used on this control-flow path}}
            scf.yield %v : !prelimhlep.lin<i1>
        } else {
            // expected-note @below {{not used on this control-flow path}}
            %u = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
            scf.yield %u : !prelimhlep.lin<i1>
        }
        scf.yield %inner : !prelimhlep.lin<i1>
    } else {
        scf.yield %v : !prelimhlep.lin<i1>
    }
    return %r : !prelimhlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !prelimhlep.lin<i1>

// Nested scf.if where a nested `then` arm uses the argument twice; the outer
// `else` also uses it once, but that alone is fine -- it's the inner double
// use that makes this control-flow path invalid. The error is anchored at
// that inner offending use.
func.func private @nested_if_double_use_in_inner_arm(%cond0: i1, %cond1: i1, %v: !prelimhlep.lin<i1>)
    -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo = #prelimhlep.halo } {
    %r0, %r1 = scf.if %cond0 -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %i0, %i1 = scf.if %cond1 -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
            // expected-error @below {{'prelimhlep.halo' function argument #2 is subject to linearity, but is used more than once on this control-flow path}}
            // expected-note @below {{used 2 times here}}
            scf.yield %v, %v : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
        } else {
            %u0 = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
            %u1 = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
            scf.yield %u0, %u1 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
        }
        scf.yield %i0, %i1 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
    } else {
        %u2 = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
        scf.yield %v, %u2 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
    }
    return %r0, %r1 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// -----

// A halo'ed argument used inside a loop body: the analysis can't determine
// how many times the loop runs, so it rejects the IR rather than guessing.
// The error is anchored at the use inside the loop.
func.func private @sink(!prelimhlep.lin<i1>) -> ()

func.func private @used_in_loop(%v: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    scf.for %i = %c0 to %c4 step %c1 {
        // expected-error @below {{'prelimhlep.halo' function argument #0 is subject to linearity, but is used inside a loop, where the number of dynamic uses cannot be determined statically}}
        func.call @sink(%v) : (!prelimhlep.lin<i1>) -> ()
    }
    return %v : !prelimhlep.lin<i1>
}

// -----

// Tests for the check that rejects regions containing a value subject to
// linearity that have more than one block, i.e. unstructured, 'cf'-dialect-
// style branching (see `checkSingleBlockRegions` in LinearityChecker.cpp).
// The rest of the linearity analysis only understands control flow
// expressed as nested regions of a `RegionBranchOpInterface` op (like
// `scf.if`); it has no notion of basic blocks or their terminators, so a
// region with several blocks joined by `cf.br`/`cf.cond_br` would silently
// make its "used on every control-flow path" reasoning unsound. Rejecting
// this structurally, rather than trying to reason about it, keeps that
// assumption honest (see prelim-hlep-halo-linearity-test.mlir for the case
// this analysis accepts: multi-block control flow confined to a region that
// never touches a linear value).

func.func private @make_qubit() -> !prelimhlep.lin<i1>

// A linear function argument that is merged back together, via `cf.br`,
// from two predecessor blocks: the checker cannot reason about this at all,
// regardless of what each predecessor does with the value.
// expected-error @below {{'prelimhlep.halo' function has a region with multiple blocks that uses a value subject to linearity; the linearity checker only understands structured control flow (e.g. 'scf.if'), not unstructured, 'cf'-dialect-style branching between blocks of the same region}}
func.func private @cf_branch_on_linear_arg(%cond: i1, %v: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    cf.cond_br %cond, ^bb1, ^bb2
^bb1:
    cf.br ^bb3(%v : !prelimhlep.lin<i1>)
^bb2:
    %u = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
    cf.br ^bb3(%u : !prelimhlep.lin<i1>)
^bb3(%r: !prelimhlep.lin<i1>):
    return %r : !prelimhlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !prelimhlep.lin<i1>
func.func private @sink(!prelimhlep.lin<i1>) -> ()

// A linear value that is only ever used in the entry block: the branching
// itself doesn't touch it, but it's still declared in (i.e. its defining
// block argument belongs to) a region that has more than one block, which
// is enough to make this analysis's reasoning about that region unsound.
// expected-error @below {{'prelimhlep.halo' function has a region with multiple blocks that uses a value subject to linearity; the linearity checker only understands structured control flow (e.g. 'scf.if'), not unstructured, 'cf'-dialect-style branching between blocks of the same region}}
func.func private @cf_branch_unrelated_to_linear_arg(%cond: i1, %v: !prelimhlep.lin<i1>) -> (i1, !prelimhlep.lin<i1>)
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    func.call @sink(%v) : (!prelimhlep.lin<i1>) -> ()
    %u = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
    cf.cond_br %cond, ^bb1, ^bb2
^bb1:
    cf.br ^bb3(%cond : i1)
^bb2:
    cf.br ^bb3(%cond : i1)
^bb3(%r: i1):
    return %r, %u : i1, !prelimhlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !prelimhlep.lin<i1>

// A region with multiple blocks where none of the blocks *directly* branch
// around the linear value: it's only ever used inside a (properly
// single-block) `scf.if` nested in one of the blocks. That doesn't help --
// the `scf.if` and its uses of the value still live in the same
// multi-block, unstructured region as the `cf.br`.
// expected-error @below {{'prelimhlep.halo' function has a region with multiple blocks that uses a value subject to linearity; the linearity checker only understands structured control flow (e.g. 'scf.if'), not unstructured, 'cf'-dialect-style branching between blocks of the same region}}
func.func private @cf_branch_containing_scf_if(%cond: i1, %v: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    cf.br ^bb1
^bb1:
    %r = scf.if %cond -> (!prelimhlep.lin<i1>) {
        scf.yield %v : !prelimhlep.lin<i1>
    } else {
        %u = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
        scf.yield %u : !prelimhlep.lin<i1>
    }
    return %r : !prelimhlep.lin<i1>
}
