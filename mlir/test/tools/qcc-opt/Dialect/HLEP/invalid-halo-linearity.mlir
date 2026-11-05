// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// Rejection tests for the control-flow linearity checker.

func.func private @make_qubit() -> !hlep.lin<i1>

// expected-error @below {{'hlep.halo' function argument #0 is subject to linearity, but is never used}}
func.func private @zero_uses(%v: !hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo = #hlep.halo } {
    %u = func.call @make_qubit() : () -> !hlep.lin<i1>
    return %u : !hlep.lin<i1>
}

// -----

func.func private @two_uses(%v: !hlep.lin<i1>) -> (!hlep.lin<i1>, !hlep.lin<i1>) attributes { hlep.halo = #hlep.halo } {
    // expected-error @below {{'hlep.halo' function argument #0 is subject to linearity, but is used more than once}}
    // expected-note @below {{used 2 times here}}
    return %v, %v : !hlep.lin<i1>, !hlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !hlep.lin<i1>

func.func private @two_uses_locally_defined(%1: !hlep.unit) -> (!hlep.lin<i1>, !hlep.lin<i1>) attributes { hlep.halo = #hlep.halo } {
    %v = func.call @make_qubit() : () -> !hlep.lin<i1>
    // expected-error @below {{'hlep.halo' result #0 of 'func.call' is subject to linearity, but is used more than once}}
    // expected-note @below {{used 2 times here}}
    return %v, %v : !hlep.lin<i1>, !hlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !hlep.lin<i1>

func.func private @if_missing_use_in_one_arm(%cond: i1, %v: !hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo = #hlep.halo } {
    // expected-error @below {{'hlep.halo' function argument #1 is subject to linearity, but is not used on every control-flow path}}
    %r = scf.if %cond -> (!hlep.lin<i1>) {
        // expected-note @below {{used on this control-flow path}}
        scf.yield %v : !hlep.lin<i1>
    } else {
        // expected-note @below {{not used on this control-flow path}}
        %u = func.call @make_qubit() : () -> !hlep.lin<i1>
        scf.yield %u : !hlep.lin<i1>
    }
    return %r : !hlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !hlep.lin<i1>

func.func private @if_double_use_in_one_arm(%cond: i1, %v: !hlep.lin<i1>) -> (!hlep.lin<i1>, !hlep.lin<i1>) attributes { hlep.halo = #hlep.halo } {
    %r0, %r1 = scf.if %cond -> (!hlep.lin<i1>, !hlep.lin<i1>) {
        // expected-error @below {{'hlep.halo' function argument #1 is subject to linearity, but is used more than once on this control-flow path}}
        // expected-note @below {{used 2 times here}}
        scf.yield %v, %v : !hlep.lin<i1>, !hlep.lin<i1>
    } else {
        %u0 = func.call @make_qubit() : () -> !hlep.lin<i1>
        %u1 = func.call @make_qubit() : () -> !hlep.lin<i1>
        scf.yield %u0, %u1 : !hlep.lin<i1>, !hlep.lin<i1>
    }
    return %r0, %r1 : !hlep.lin<i1>, !hlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !hlep.lin<i1>

func.func private @nested_if_missing_use_in_inner_arm(%cond0: i1, %cond1: i1, %v: !hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo = #hlep.halo } {
    %r = scf.if %cond0 -> (!hlep.lin<i1>) {
        // expected-error @below {{'hlep.halo' function argument #2 is subject to linearity, but is not used on every control-flow path}}
        %inner = scf.if %cond1 -> (!hlep.lin<i1>) {
            // expected-note @below {{used on this control-flow path}}
            scf.yield %v : !hlep.lin<i1>
        } else {
            // expected-note @below {{not used on this control-flow path}}
            %u = func.call @make_qubit() : () -> !hlep.lin<i1>
            scf.yield %u : !hlep.lin<i1>
        }
        scf.yield %inner : !hlep.lin<i1>
    } else {
        scf.yield %v : !hlep.lin<i1>
    }
    return %r : !hlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !hlep.lin<i1>

func.func private @nested_if_double_use_in_inner_arm(%cond0: i1, %cond1: i1, %v: !hlep.lin<i1>)
    -> (!hlep.lin<i1>, !hlep.lin<i1>) attributes { hlep.halo = #hlep.halo } {
    %r0, %r1 = scf.if %cond0 -> (!hlep.lin<i1>, !hlep.lin<i1>) {
        %i0, %i1 = scf.if %cond1 -> (!hlep.lin<i1>, !hlep.lin<i1>) {
            // expected-error @below {{'hlep.halo' function argument #2 is subject to linearity, but is used more than once on this control-flow path}}
            // expected-note @below {{used 2 times here}}
            scf.yield %v, %v : !hlep.lin<i1>, !hlep.lin<i1>
        } else {
            %u0 = func.call @make_qubit() : () -> !hlep.lin<i1>
            %u1 = func.call @make_qubit() : () -> !hlep.lin<i1>
            scf.yield %u0, %u1 : !hlep.lin<i1>, !hlep.lin<i1>
        }
        scf.yield %i0, %i1 : !hlep.lin<i1>, !hlep.lin<i1>
    } else {
        %u2 = func.call @make_qubit() : () -> !hlep.lin<i1>
        scf.yield %v, %u2 : !hlep.lin<i1>, !hlep.lin<i1>
    }
    return %r0, %r1 : !hlep.lin<i1>, !hlep.lin<i1>
}

// -----

func.func private @sink(!hlep.lin<i1>) -> ()

func.func private @used_in_loop(%v: !hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo = #hlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    scf.for %i = %c0 to %c4 step %c1 {
        // expected-error @below {{'hlep.halo' function argument #0 is subject to linearity, but is used inside a loop, where the number of dynamic uses cannot be determined statically}}
        func.call @sink(%v) : (!hlep.lin<i1>) -> ()
    }
    return %v : !hlep.lin<i1>
}

// -----

// Rejection of multi-block regions that use values subject to linearity.

func.func private @make_qubit() -> !hlep.lin<i1>

// expected-error @below {{'hlep.halo' function has a region with multiple blocks that uses a value subject to linearity; the linearity checker only understands structured control flow (e.g. 'scf.if'), not unstructured, 'cf'-dialect-style branching between blocks of the same region}}
func.func private @cf_branch_on_linear_arg(%cond: i1, %v: !hlep.lin<i1>) -> !hlep.lin<i1>
    attributes { hlep.halo = #hlep.halo } {
    cf.cond_br %cond, ^bb1, ^bb2
^bb1:
    cf.br ^bb3(%v : !hlep.lin<i1>)
^bb2:
    %u = func.call @make_qubit() : () -> !hlep.lin<i1>
    cf.br ^bb3(%u : !hlep.lin<i1>)
^bb3(%r: !hlep.lin<i1>):
    return %r : !hlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !hlep.lin<i1>
func.func private @sink(!hlep.lin<i1>) -> ()

// For now the checker is strict: even if we only use the linear value in the entry block, it gets rejected.
// TODO: See if we can relax this.
// expected-error @below {{'hlep.halo' function has a region with multiple blocks that uses a value subject to linearity; the linearity checker only understands structured control flow (e.g. 'scf.if'), not unstructured, 'cf'-dialect-style branching between blocks of the same region}}
func.func private @cf_branch_unrelated_to_linear_arg(%cond: i1, %v: !hlep.lin<i1>) -> (i1, !hlep.lin<i1>)
    attributes { hlep.halo = #hlep.halo } {
    func.call @sink(%v) : (!hlep.lin<i1>) -> ()
    %u = func.call @make_qubit() : () -> !hlep.lin<i1>
    cf.cond_br %cond, ^bb1, ^bb2
^bb1:
    cf.br ^bb3(%cond : i1)
^bb2:
    cf.br ^bb3(%cond : i1)
^bb3(%r: i1):
    return %r, %u : i1, !hlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !hlep.lin<i1>

// expected-error @below {{'hlep.halo' function has a region with multiple blocks that uses a value subject to linearity; the linearity checker only understands structured control flow (e.g. 'scf.if'), not unstructured, 'cf'-dialect-style branching between blocks of the same region}}
func.func private @cf_branch_containing_scf_if(%cond: i1, %v: !hlep.lin<i1>) -> !hlep.lin<i1>
    attributes { hlep.halo = #hlep.halo } {
    cf.br ^bb1
^bb1:
    %r = scf.if %cond -> (!hlep.lin<i1>) {
        scf.yield %v : !hlep.lin<i1>
    } else {
        %u = func.call @make_qubit() : () -> !hlep.lin<i1>
        scf.yield %u : !hlep.lin<i1>
    }
    return %r : !hlep.lin<i1>
}

// -----

// Rejection of ops that are not linearity-aware but have operands, results, or
// region arguments subject to linearity.

func.func private @make_qubit() -> !hlep.lin<i1>

// Only one of the select's operands is ever produced, the other one is silently
// discarded.
func.func private @select_between_linear_values(%cond: i1, %v: !hlep.lin<i1>) -> !hlep.lin<i1>
    attributes { hlep.halo = #hlep.halo } {
    %u = func.call @make_qubit() : () -> !hlep.lin<i1>
    // expected-error @below {{'hlep.halo' function uses a value subject to linearity as an operand, result, or region argument of 'arith.select', which is not linearity-aware (does not implement 'LinearityAwareOpInterface')}}
    %r = arith.select %cond, %v, %u : !hlep.lin<i1>
    return %r : !hlep.lin<i1>
}

// -----

// An op that is not linearity-aware producing a value subject to linearity.
func.func private @linear_result_of_unaware_op(%b: i1) -> !hlep.lin<i1>
    attributes { hlep.halo = #hlep.halo } {
    // expected-error @below {{'hlep.halo' function uses a value subject to linearity as an operand, result, or region argument of 'builtin.unrealized_conversion_cast', which is not linearity-aware (does not implement 'LinearityAwareOpInterface')}}
    %v = builtin.unrealized_conversion_cast %b : i1 to !hlep.lin<i1>
    return %v : !hlep.lin<i1>
}

// -----

func.func private @sink(!hlep.lin<i1>) -> ()

// The use itself is by a linearity-aware op, but it is nested in the body of
// `tensor.generate`, which runs once per tensor element.
func.func private @used_inside_unaware_region(%v: !hlep.lin<i1>) -> (tensor<4xi1>, !hlep.unit)
    attributes { hlep.halo = #hlep.halo } {
    %false = arith.constant false
    // expected-note @below {{enclosing operation}}
    %t = tensor.generate {
    ^bb0(%j : index):
        // expected-error @below {{'hlep.halo' function argument #0 is subject to linearity, but is used inside a region of 'tensor.generate', which is not linearity-aware (does not implement 'LinearityAwareOpInterface')}}
        func.call @sink(%v) : (!hlep.lin<i1>) -> ()
        tensor.yield %false : i1
    } : tensor<4xi1>
    %unit = hlep.unit_value : !hlep.unit
    return %t, %unit : tensor<4xi1>, !hlep.unit
}

// -----

func.func private @make_register() -> !hlep.lin<i4>

// The loop body drops the carried register and yields a fresh one instead.
func.func private @loop_drops_carried_value(%state : !hlep.lin<i4>) -> !hlep.lin<i4> attributes { hlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    // expected-error @below {{'hlep.halo' block argument #1 is subject to linearity, but is never used}}
    %out = scf.for %i = %c0 to %c4 step %c1 iter_args(%reg = %state) -> (!hlep.lin<i4>) {
        %fresh = func.call @make_register() : () -> !hlep.lin<i4>
        scf.yield %fresh : !hlep.lin<i4>
    }
    return %out : !hlep.lin<i4>
}

// -----

func.func private @extract_4(!hlep.lin<i4>, index) -> (!hlep.lin<i3>, !hlep.lin<i1>) attributes { hlep.halo }
func.func private @insert_4(!hlep.lin<i3>, !hlep.lin<i1>, index) -> !hlep.lin<i4> attributes { hlep.halo }
func.func private @make_qubit() -> !hlep.lin<i1>

// The extracted qubit is dropped, and a fresh qubit is inserted in its place.
func.func private @loop_drops_extracted_qubit(%state : !hlep.lin<i4>) -> !hlep.lin<i4> attributes { hlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    %out = scf.for %i = %c0 to %c4 step %c1 iter_args(%reg = %state) -> (!hlep.lin<i4>) {
        // expected-error @below {{'hlep.halo' result #1 of 'func.call' is subject to linearity, but is never used}}
        %rest, %qubit = func.call @extract_4(%reg, %i) : (!hlep.lin<i4>, index) -> (!hlep.lin<i3>, !hlep.lin<i1>)
        %fresh = func.call @make_qubit() : () -> !hlep.lin<i1>
        %next = func.call @insert_4(%rest, %fresh, %i) : (!hlep.lin<i3>, !hlep.lin<i1>, index) -> !hlep.lin<i4>
        scf.yield %next : !hlep.lin<i4>
    }
    return %out : !hlep.lin<i4>
}

// -----

func.func private @extract_4(!hlep.lin<i4>, index) -> (!hlep.lin<i3>, !hlep.lin<i1>) attributes { hlep.halo }
func.func private @insert_4(!hlep.lin<i3>, !hlep.lin<i1>, index) -> !hlep.lin<i4> attributes { hlep.halo }
func.func private @consume_register(!hlep.lin<i4>) -> ()

// The carried register is extracted from twice in the same iteration.
func.func private @loop_extracts_twice(%state : !hlep.lin<i4>) -> !hlep.lin<i4> attributes { hlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    %out = scf.for %i = %c0 to %c4 step %c1 iter_args(%reg = %state) -> (!hlep.lin<i4>) {
        // expected-error @below {{'hlep.halo' block argument #1 is subject to linearity, but is used more than once}}
        // expected-note @below {{used here}}
        %rest, %qubit = func.call @extract_4(%reg, %i) : (!hlep.lin<i4>, index) -> (!hlep.lin<i3>, !hlep.lin<i1>)
        // expected-note @below {{used here}}
        %rest_again, %qubit_again = func.call @extract_4(%reg, %i) : (!hlep.lin<i4>, index) -> (!hlep.lin<i3>, !hlep.lin<i1>)
        %next = func.call @insert_4(%rest, %qubit, %i) : (!hlep.lin<i3>, !hlep.lin<i1>, index) -> !hlep.lin<i4>
        %next_again = func.call @insert_4(%rest_again, %qubit_again, %i) : (!hlep.lin<i3>, !hlep.lin<i1>, index) -> !hlep.lin<i4>
        func.call @consume_register(%next_again) : (!hlep.lin<i4>) -> ()
        scf.yield %next : !hlep.lin<i4>
    }
    return %out : !hlep.lin<i4>
}

// -----

// The register carried out of the loop is never used.
func.func private @loop_result_dropped(%state : !hlep.lin<i4>) -> !hlep.unit attributes { hlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    // expected-error @below {{'hlep.halo' result #0 of 'scf.for' is subject to linearity, but is never used}}
    %out = scf.for %i = %c0 to %c4 step %c1 iter_args(%reg = %state) -> (!hlep.lin<i4>) {
        scf.yield %reg : !hlep.lin<i4>
    }
    %unit = hlep.unit_value : !hlep.unit
    return %unit : !hlep.unit
}
