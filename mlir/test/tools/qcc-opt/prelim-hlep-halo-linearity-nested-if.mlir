// RUN: qcc-opt %s | FileCheck %s

// Positive tests for the control-flow linearity check performed by
// `PrelimHLEPDialect::verifyOperationAttribute` on `prelim_hlep.halo`
// function arguments (see `checkPreciselyOneUse` / `checkUsesCoverRegion` in
// LinearityChecker.cpp), specifically its support for nested branching: a
// halo'ed argument can be used exactly once per leaf of a tree of nested
// `scf.if`s, as long as every leaf uses it and no leaf uses it more than
// once. If any of these functions failed to verify, qcc-opt would emit an
// error and FileCheck would fail to find the corresponding CHECK-LABEL (see
// prelim-hlep-halo-linearity-errors.mlir for the cases this analysis
// rejects, including nested variants of these that omit or double a use).

func.func private @make_qubit() -> !prelimhlep.lin<i1>

// Two levels of nesting, one use in each of the four leaves.
func.func private @nested_if_one_use_per_leaf(%cond0: i1, %cond1: i1, %v: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    %r = scf.if %cond0 -> (!prelimhlep.lin<i1>) {
        %inner = scf.if %cond1 -> (!prelimhlep.lin<i1>) {
            scf.yield %v : !prelimhlep.lin<i1>
        } else {
            scf.yield %v : !prelimhlep.lin<i1>
        }
        scf.yield %inner : !prelimhlep.lin<i1>
    } else {
        %inner = scf.if %cond1 -> (!prelimhlep.lin<i1>) {
            scf.yield %v : !prelimhlep.lin<i1>
        } else {
            scf.yield %v : !prelimhlep.lin<i1>
        }
        scf.yield %inner : !prelimhlep.lin<i1>
    }
    return %r : !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func private @nested_if_one_use_per_leaf

// Asymmetric nesting: the outer `else` uses the argument directly, while the
// outer `then` defers to a nested if that uses it once in each of its arms.
func.func private @nested_if_asymmetric(%cond0: i1, %cond1: i1, %v: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    %r = scf.if %cond0 -> (!prelimhlep.lin<i1>) {
        %inner = scf.if %cond1 -> (!prelimhlep.lin<i1>) {
            scf.yield %v : !prelimhlep.lin<i1>
        } else {
            scf.yield %v : !prelimhlep.lin<i1>
        }
        scf.yield %inner : !prelimhlep.lin<i1>
    } else {
        scf.yield %v : !prelimhlep.lin<i1>
    }
    return %r : !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func private @nested_if_asymmetric

// Three levels of nesting, one use in each of the eight leaves.
func.func private @triple_nested_if_one_use_per_leaf(%cond0: i1, %cond1: i1, %cond2: i1, %v: !prelimhlep.lin<i1>)
    -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %r = scf.if %cond0 -> (!prelimhlep.lin<i1>) {
        %mid = scf.if %cond1 -> (!prelimhlep.lin<i1>) {
            %inner = scf.if %cond2 -> (!prelimhlep.lin<i1>) {
                scf.yield %v : !prelimhlep.lin<i1>
            } else {
                scf.yield %v : !prelimhlep.lin<i1>
            }
            scf.yield %inner : !prelimhlep.lin<i1>
        } else {
            scf.yield %v : !prelimhlep.lin<i1>
        }
        scf.yield %mid : !prelimhlep.lin<i1>
    } else {
        scf.yield %v : !prelimhlep.lin<i1>
    }
    return %r : !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func private @triple_nested_if_one_use_per_leaf

// Nesting on both arms of the outer if, with an unconditional use of a
// second, unrelated halo'ed argument thrown in to make sure the two don't
// interfere with each other's analysis.
func.func private @nested_if_two_halo_args(%cond0: i1, %cond1: i1, %v: !prelimhlep.lin<i1>, %w: !prelimhlep.lin<i1>)
    -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo = #prelimhlep.halo } {
    %r = scf.if %cond0 -> (!prelimhlep.lin<i1>) {
        %inner = scf.if %cond1 -> (!prelimhlep.lin<i1>) {
            scf.yield %v : !prelimhlep.lin<i1>
        } else {
            scf.yield %v : !prelimhlep.lin<i1>
        }
        scf.yield %inner : !prelimhlep.lin<i1>
    } else {
        scf.yield %v : !prelimhlep.lin<i1>
    }
    return %r, %w : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func private @nested_if_two_halo_args

// Two consecutive ifs, consuming different linear values.
func.func private @irrelevant_branching(%cond0: i1, %cond1: i1, %v: !prelimhlep.lin<i1>, %w: !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>)
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    %first = scf.if %cond1 -> (!prelimhlep.lin<i1>) {
        scf.yield %v : !prelimhlep.lin<i1>
    } else {
        scf.yield %v : !prelimhlep.lin<i1>
    }
    %second = scf.if %cond1 -> (!prelimhlep.lin<i1>) {
        scf.yield %w : !prelimhlep.lin<i1>
    } else {
        scf.yield %w : !prelimhlep.lin<i1>
    }
    return %first, %second : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func private @irrelevant_branching
