// RUN: qcc-opt %s | FileCheck %s

// Positive tests for the control-flow linearity check performed by
// `PrelimHLEPDialect::verifyOperationAttribute` on `prelim_hlep.halo`
// functions.

func.func private @make_qubit() -> !prelimhlep.lin<i1>

// The linearity check proves this is fine: %v is used exactly once on
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

// Three levels of nesting, one use in each leaf.
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

// Multi-block regions are regected if they contain values subject to linearity.
// Here, the qubit is not used in the unstructured control flow region, so the program is legal.
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

// Select-like ops are rejected if their arguments are subject to linearity.
// Here, `arith.select` is used on a classical value, so the program is legal.
func.func @select_on_classical_value_ok(%cond: i1, %v: !prelimhlep.lin<i1>) -> (i1, !prelimhlep.lin<i1>)
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    %true = arith.constant true
    %false = arith.constant false
    %r = arith.select %cond, %true, %false : i1
    return %r, %v : i1, !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func @select_on_classical_value_ok

// Loops: a value subject to linearity may be carried through an `scf.for`
// (as `iter_args` operand, block argument, `scf.yield` operand, and result),
// as long as each of these is used exactly once per iteration.

func.func private @gate(!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo }

// Two linear values carried through a loop and swapped in every iteration.
func.func private @swap_carried_values(%a : !prelimhlep.lin<i1>, %b : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>)
    attributes { prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c3 = arith.constant 3 : index
    %out:2 = scf.for %i = %c0 to %c3 step %c1 iter_args(%x = %a, %y = %b) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %gated = func.call @gate(%x) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
        scf.yield %y, %gated : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
    }
    return %out#0, %out#1 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func private @swap_carried_values

// Helper.
// Lin of (x, i) |-> (x without element i, element i) on a register of type
// `!prelimhlep.lin<tensor<4xi1>>`, with the index captured, i.e. classical.
// The delinearized register is an ordinary classical tensor.
func.func private @extract_tensor_4(%reg : !prelimhlep.lin<tensor<4xi1>>, %i : index) -> (!prelimhlep.lin<tensor<3xi1>>, !prelimhlep.lin<i1>)
    attributes { prelimhlep.halo } {
    %rest, %qubit = prelimhlep.lin (
        %bits : tensor<4xi1> from %reg : !prelimhlep.lin<tensor<4xi1>>
    ) -> (!prelimhlep.lin<tensor<3xi1>>, !prelimhlep.lin<i1>) {
        %c1 = arith.constant 1 : index
        %bit = tensor.extract %bits[%i] : tensor<4xi1>
        %rest_bits = tensor.generate {
        ^bb0(%j : index):
            %before = arith.cmpi ult, %j, %i : index
            %j_next = arith.addi %j, %c1 : index
            %k = arith.select %before, %j, %j_next : index
            %b = tensor.extract %bits[%k] : tensor<4xi1>
            tensor.yield %b : i1
        } : tensor<3xi1>
        prelimhlep.output (%rest_bits : tensor<3xi1>, %bit : i1)
    }
    return %rest, %qubit : !prelimhlep.lin<tensor<3xi1>>, !prelimhlep.lin<i1>
}
// CHECK-LABEL: func.func private @extract_tensor_4

// Helper. Inverse of @extract_tensor_4.
func.func private @insert_tensor_4(%rest : !prelimhlep.lin<tensor<3xi1>>, %qubit : !prelimhlep.lin<i1>, %i : index) -> !prelimhlep.lin<tensor<4xi1>>
    attributes { prelimhlep.halo } {
    %reg = prelimhlep.lin (
        %rest_bits : tensor<3xi1> from %rest : !prelimhlep.lin<tensor<3xi1>>,
        %bit : i1 from %qubit : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<tensor<4xi1>>) {
        %c1 = arith.constant 1 : index
        %bits = tensor.generate {
        ^bb0(%j : index):
            %at = arith.cmpi eq, %j, %i : index
            %b = scf.if %at -> i1 {
                scf.yield %bit : i1
            } else {
                %before = arith.cmpi ult, %j, %i : index
                %j_prev = arith.subi %j, %c1 : index
                %k = arith.select %before, %j, %j_prev : index
                %r = tensor.extract %rest_bits[%k] : tensor<3xi1>
                scf.yield %r : i1
            }
            tensor.yield %b : i1
        } : tensor<4xi1>
        prelimhlep.output (%bits : tensor<4xi1>)
    }
    return %reg : !prelimhlep.lin<tensor<4xi1>>
}
// CHECK-LABEL: func.func private @insert_tensor_4

// A gate on every qubit of a tensor register, one per iteration.
func.func private @gate_on_every_tensor_element(%state : !prelimhlep.lin<tensor<4xi1>>) -> !prelimhlep.lin<tensor<4xi1>>
    attributes { prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    %out = scf.for %i = %c0 to %c4 step %c1 iter_args(%reg = %state) -> (!prelimhlep.lin<tensor<4xi1>>) {
        %rest, %qubit = func.call @extract_tensor_4(%reg, %i) : (!prelimhlep.lin<tensor<4xi1>>, index) -> (!prelimhlep.lin<tensor<3xi1>>, !prelimhlep.lin<i1>)
        %gated = func.call @gate(%qubit) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
        %next = func.call @insert_tensor_4(%rest, %gated, %i) : (!prelimhlep.lin<tensor<3xi1>>, !prelimhlep.lin<i1>, index) -> !prelimhlep.lin<tensor<4xi1>>
        scf.yield %next : !prelimhlep.lin<tensor<4xi1>>
    }
    return %out : !prelimhlep.lin<tensor<4xi1>>
}
// CHECK-LABEL: func.func private @gate_on_every_tensor_element
