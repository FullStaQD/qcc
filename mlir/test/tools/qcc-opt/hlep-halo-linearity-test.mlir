// RUN: qcc-opt %s | FileCheck %s

// Positive tests for the control-flow linearity check performed by
// `HLEPDialect::verifyOperationAttribute` on `hlep.halo`
// functions.

func.func private @make_qubit() -> !hlep.lin<i1>

// The linearity check proves this is fine: %v is used exactly once on
// both the `then` and `else` paths of the scf.if.
func.func @halo_linearity_if_ok(%cond: i1, %v: !hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo = #hlep.halo } {
    %r = scf.if %cond -> (!hlep.lin<i1>) {
        scf.yield %v : !hlep.lin<i1>
    } else {
        scf.yield %v : !hlep.lin<i1>
    }
    return %r : !hlep.lin<i1>
}
// CHECK-LABEL: func.func @halo_linearity_if_ok

// Nested branching: a halo'ed argument can be used exactly once per leaf of
// a tree of nested `scf.if`s, as long as every leaf uses it and no leaf uses
// it more than once.

// Two levels of nesting, one use in each of the four leaves.
func.func private @nested_if_one_use_per_leaf(%cond0: i1, %cond1: i1, %v: !hlep.lin<i1>) -> !hlep.lin<i1>
    attributes { hlep.halo = #hlep.halo } {
    %r = scf.if %cond0 -> (!hlep.lin<i1>) {
        %inner = scf.if %cond1 -> (!hlep.lin<i1>) {
            scf.yield %v : !hlep.lin<i1>
        } else {
            scf.yield %v : !hlep.lin<i1>
        }
        scf.yield %inner : !hlep.lin<i1>
    } else {
        %inner = scf.if %cond1 -> (!hlep.lin<i1>) {
            scf.yield %v : !hlep.lin<i1>
        } else {
            scf.yield %v : !hlep.lin<i1>
        }
        scf.yield %inner : !hlep.lin<i1>
    }
    return %r : !hlep.lin<i1>
}
// CHECK-LABEL: func.func private @nested_if_one_use_per_leaf

// Asymmetric nesting: the outer `else` uses the argument directly, while the
// outer `then` defers to a nested if that uses it once in each of its arms.
func.func private @nested_if_asymmetric(%cond0: i1, %cond1: i1, %v: !hlep.lin<i1>) -> !hlep.lin<i1>
    attributes { hlep.halo = #hlep.halo } {
    %r = scf.if %cond0 -> (!hlep.lin<i1>) {
        %inner = scf.if %cond1 -> (!hlep.lin<i1>) {
            scf.yield %v : !hlep.lin<i1>
        } else {
            scf.yield %v : !hlep.lin<i1>
        }
        scf.yield %inner : !hlep.lin<i1>
    } else {
        scf.yield %v : !hlep.lin<i1>
    }
    return %r : !hlep.lin<i1>
}
// CHECK-LABEL: func.func private @nested_if_asymmetric

// Three levels of nesting, one use in each leaf.
func.func private @triple_nested_if_one_use_per_leaf(%cond0: i1, %cond1: i1, %cond2: i1, %v: !hlep.lin<i1>)
    -> !hlep.lin<i1> attributes { hlep.halo = #hlep.halo } {
    %r = scf.if %cond0 -> (!hlep.lin<i1>) {
        %mid = scf.if %cond1 -> (!hlep.lin<i1>) {
            %inner = scf.if %cond2 -> (!hlep.lin<i1>) {
                scf.yield %v : !hlep.lin<i1>
            } else {
                scf.yield %v : !hlep.lin<i1>
            }
            scf.yield %inner : !hlep.lin<i1>
        } else {
            scf.yield %v : !hlep.lin<i1>
        }
        scf.yield %mid : !hlep.lin<i1>
    } else {
        scf.yield %v : !hlep.lin<i1>
    }
    return %r : !hlep.lin<i1>
}
// CHECK-LABEL: func.func private @triple_nested_if_one_use_per_leaf

// Two consecutive ifs, consuming different linear values.
func.func private @irrelevant_branching(%cond0: i1, %cond1: i1, %v: !hlep.lin<i1>, %w: !hlep.lin<i1>) -> (!hlep.lin<i1>, !hlep.lin<i1>)
    attributes { hlep.halo = #hlep.halo } {
    %first = scf.if %cond1 -> (!hlep.lin<i1>) {
        scf.yield %v : !hlep.lin<i1>
    } else {
        scf.yield %v : !hlep.lin<i1>
    }
    %second = scf.if %cond1 -> (!hlep.lin<i1>) {
        scf.yield %w : !hlep.lin<i1>
    } else {
        scf.yield %w : !hlep.lin<i1>
    }
    return %first, %second : !hlep.lin<i1>, !hlep.lin<i1>
}
// CHECK-LABEL: func.func private @irrelevant_branching

// Multi-block regions are regected if they contain values subject to linearity.
// Here, the qubit is not used in the unstructured control flow region, so the program is legal.
func.func @cf_branching_in_subregion_on_classical_value_ok(%cond: i1, %v: !hlep.lin<i1>) -> (i1, !hlep.lin<i1>)
    attributes { hlep.halo = #hlep.halo } {
    %r = scf.execute_region -> i1 {
        cf.cond_br %cond, ^bb1, ^bb2
    ^bb1:
        cf.br ^bb3(%cond : i1)
    ^bb2:
        cf.br ^bb3(%cond : i1)
    ^bb3(%x: i1):
        scf.yield %x : i1
    }
    return %r, %v : i1, !hlep.lin<i1>
}
// CHECK-LABEL: func.func @cf_branching_in_subregion_on_classical_value_ok

// Ops that are not linearity-aware (e.g. `arith.select`) are rejected only if
// they handle values subject to linearity. Here, `arith.select` is used on a
// classical value, so the program is legal.
func.func @select_on_classical_value_ok(%cond: i1, %v: !hlep.lin<i1>) -> (i1, !hlep.lin<i1>)
    attributes { hlep.halo = #hlep.halo } {
    %true = arith.constant true
    %false = arith.constant false
    %r = arith.select %cond, %true, %false : i1
    return %r, %v : i1, !hlep.lin<i1>
}
// CHECK-LABEL: func.func @select_on_classical_value_ok

// Loops: a value subject to linearity may be carried through an `scf.for`
// (as `iter_args` operand, block argument, `scf.yield` operand, and result),
// as long as each of these is used exactly once per iteration.

func.func private @gate(!hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo }

// Two linear values carried through a loop and swapped in every iteration.
func.func private @swap_carried_values(%a : !hlep.lin<i1>, %b : !hlep.lin<i1>) -> (!hlep.lin<i1>, !hlep.lin<i1>)
    attributes { hlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c3 = arith.constant 3 : index
    %out:2 = scf.for %i = %c0 to %c3 step %c1 iter_args(%x = %a, %y = %b) -> (!hlep.lin<i1>, !hlep.lin<i1>) {
        %gated = func.call @gate(%x) : (!hlep.lin<i1>) -> !hlep.lin<i1>
        scf.yield %y, %gated : !hlep.lin<i1>, !hlep.lin<i1>
    }
    return %out#0, %out#1 : !hlep.lin<i1>, !hlep.lin<i1>
}
// CHECK-LABEL: func.func private @swap_carried_values

// Helper.
// Lin of (x, i) |-> (x without element i, element i) on a register of type
// `!hlep.lin<tensor<4xi1>>`, with the index captured, i.e. classical.
// The delinearized register is an ordinary classical tensor.
func.func private @extract_tensor_4(%reg : !hlep.lin<tensor<4xi1>>, %i : index) -> (!hlep.lin<tensor<3xi1>>, !hlep.lin<i1>)
    attributes { hlep.halo } {
    %rest, %qubit = hlep.lin (
        %bits : tensor<4xi1> from %reg : !hlep.lin<tensor<4xi1>>
    ) -> (!hlep.lin<tensor<3xi1>>, !hlep.lin<i1>) {
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
        hlep.output (%rest_bits : tensor<3xi1>, %bit : i1)
    }
    return %rest, %qubit : !hlep.lin<tensor<3xi1>>, !hlep.lin<i1>
}
// CHECK-LABEL: func.func private @extract_tensor_4

// Helper. Inverse of @extract_tensor_4.
func.func private @insert_tensor_4(%rest : !hlep.lin<tensor<3xi1>>, %qubit : !hlep.lin<i1>, %i : index) -> !hlep.lin<tensor<4xi1>>
    attributes { hlep.halo } {
    %reg = hlep.lin (
        %rest_bits : tensor<3xi1> from %rest : !hlep.lin<tensor<3xi1>>,
        %bit : i1 from %qubit : !hlep.lin<i1>
    ) -> (!hlep.lin<tensor<4xi1>>) {
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
        hlep.output (%bits : tensor<4xi1>)
    }
    return %reg : !hlep.lin<tensor<4xi1>>
}
// CHECK-LABEL: func.func private @insert_tensor_4

// A gate on every qubit of a tensor register, one per iteration.
func.func private @gate_on_every_tensor_element(%state : !hlep.lin<tensor<4xi1>>) -> !hlep.lin<tensor<4xi1>>
    attributes { hlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    %out = scf.for %i = %c0 to %c4 step %c1 iter_args(%reg = %state) -> (!hlep.lin<tensor<4xi1>>) {
        %rest, %qubit = func.call @extract_tensor_4(%reg, %i) : (!hlep.lin<tensor<4xi1>>, index) -> (!hlep.lin<tensor<3xi1>>, !hlep.lin<i1>)
        %gated = func.call @gate(%qubit) : (!hlep.lin<i1>) -> !hlep.lin<i1>
        %next = func.call @insert_tensor_4(%rest, %gated, %i) : (!hlep.lin<tensor<3xi1>>, !hlep.lin<i1>, index) -> !hlep.lin<tensor<4xi1>>
        scf.yield %next : !hlep.lin<tensor<4xi1>>
    }
    return %out : !hlep.lin<tensor<4xi1>>
}
// CHECK-LABEL: func.func private @gate_on_every_tensor_element

// Other structured control flow may forward values subject to linearity, too.

// A linear value carried through an `scf.while`, through both its `before`
// region (via `scf.condition`) and its `after` region (via `scf.yield`).
func.func private @while_carries_value(%v : !hlep.lin<i1>, %n : index) -> !hlep.lin<i1>
    attributes { hlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %out:2 = scf.while (%i = %c0, %x = %v) : (index, !hlep.lin<i1>) -> (index, !hlep.lin<i1>) {
        %continue = arith.cmpi ult, %i, %n : index
        scf.condition(%continue) %i, %x : index, !hlep.lin<i1>
    } do {
    ^bb0(%i : index, %x : !hlep.lin<i1>):
        %gated = func.call @gate(%x) : (!hlep.lin<i1>) -> !hlep.lin<i1>
        %i_next = arith.addi %i, %c1 : index
        scf.yield %i_next, %gated : index, !hlep.lin<i1>
    }
    return %out#1 : !hlep.lin<i1>
}
// CHECK-LABEL: func.func private @while_carries_value

// A linear value used exactly once in every case of an `scf.index_switch`.
func.func private @index_switch_uses_value_in_every_case(%v : !hlep.lin<i1>, %k : index) -> !hlep.lin<i1>
    attributes { hlep.halo } {
    %r = scf.index_switch %k -> !hlep.lin<i1>
    case 0 {
        %gated = func.call @gate(%v) : (!hlep.lin<i1>) -> !hlep.lin<i1>
        scf.yield %gated : !hlep.lin<i1>
    }
    default {
        scf.yield %v : !hlep.lin<i1>
    }
    return %r : !hlep.lin<i1>
}
// CHECK-LABEL: func.func private @index_switch_uses_value_in_every_case

// A linear value passed through an `scf.execute_region`.
func.func private @execute_region_forwards_value(%v : !hlep.lin<i1>) -> !hlep.lin<i1>
    attributes { hlep.halo } {
    %r = scf.execute_region -> !hlep.lin<i1> {
        %gated = func.call @gate(%v) : (!hlep.lin<i1>) -> !hlep.lin<i1>
        scf.yield %gated : !hlep.lin<i1>
    }
    return %r : !hlep.lin<i1>
}
// CHECK-LABEL: func.func private @execute_region_forwards_value
