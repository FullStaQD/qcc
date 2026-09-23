// RUN: qcc-opt %s | FileCheck %s

// Positive tests for the control-flow linearity check performed by
// `PrelimHLEPDialect::verifyOperationAttribute` on `prelim_hlep.halo`
// function arguments (see `checkPreciselyOneUse` / `checkUsesCoverRegion` /
// `checkSingleBlockRegions` in LinearityChecker.cpp). If any of these
// functions failed to verify, qcc-opt would emit an error and FileCheck
// would fail to find the corresponding CHECK-LABEL (see
// prelim-hlep-halo-linearity-errors.mlir for the cases this analysis
// rejects).

func.func private @make_qubit() -> !prelimhlep.lin<i1>

// Nested branching: a halo'ed argument can be used exactly once per leaf of
// a tree of nested `scf.if`s, as long as every leaf uses it and no leaf uses
// it more than once.

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

// The single-block-region check (`checkSingleBlockRegions`) only rejects a
// region with several blocks if it contains a value subject to linearity.
// This function's top-level body is a single block (so it's unaffected
// regardless of what it contains), and it does use its halo'ed argument,
// unconditionally, exactly once -- but it also nests an `scf.execute_region`
// whose *own* body has several blocks (joined by `cf.br`) and touches only
// the classical %cond value, never the linear one. That's fine: the
// multi-block region and the linear value never appear in the same region
// (see prelim-hlep-halo-linearity-errors.mlir for the cases where they do).
func.func @cf_branching_in_subregion_on_classical_value_ok(%cond: i1, %v: !prelimhlep.lin<i1>) -> (i1, !prelimhlep.lin<i1>)
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    %r = scf.execute_region -> i1 {
        cf.cond_br %cond, ^bb1, ^bb2
    ^bb1:
        cf.br ^bb3(%cond : i1)
    ^bb2:
        cf.br ^bb3(%cond : i1)
    ^bb3(%x: i1):
        scf.yield %x : i1
    }
    return %r, %v : i1, !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func @cf_branching_in_subregion_on_classical_value_ok

// The select check (`checkNoSelectOfLinearValues`) only rejects an
// `arith.select` (or other `SelectLikeOpInterface` op) whose operands or
// result are subject to linearity; selecting between two classical values,
// alongside an unconditional, unrelated use of the halo'ed argument, is
// fine (see prelim-hlep-halo-linearity-errors.mlir for the case where the
// select itself touches a linear value).
func.func @select_on_classical_value_ok(%cond: i1, %v: !prelimhlep.lin<i1>) -> (i1, !prelimhlep.lin<i1>)
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    %true = arith.constant true
    %false = arith.constant false
    %r = arith.select %cond, %true, %false : i1
    return %r, %v : i1, !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func @select_on_classical_value_ok
