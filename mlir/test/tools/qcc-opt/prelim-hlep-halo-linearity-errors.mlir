// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// Rejection tests for the control-flow linearity checker.

func.func private @make_qubit() -> !prelimhlep.lin<i1>

// expected-error @below {{'prelimhlep.halo' function argument #0 is subject to linearity, but is never used}}
func.func private @zero_uses(%v: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    %u = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
    return %u : !prelimhlep.lin<i1>
}

// -----

func.func private @two_uses(%v: !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{'prelimhlep.halo' function argument #0 is subject to linearity, but is used more than once}}
    // expected-note @below {{used 2 times here}}
    return %v, %v : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !prelimhlep.lin<i1>

func.func private @two_uses_locally_defined(%1: !prelimhlep.unit) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo = #prelimhlep.halo } {
    %v = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
    // expected-error @below {{'prelimhlep.halo' result #0 of 'func.call' is subject to linearity, but is used more than once}}
    // expected-note @below {{used 2 times here}}
    return %v, %v : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// -----

func.func private @make_qubit() -> !prelimhlep.lin<i1>

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

// Rejection of multi-block regions that use values subject to linearity.

func.func private @make_qubit() -> !prelimhlep.lin<i1>

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

// For now the checker is strict: even if we only use the linear value in the entry block, it gets rejected.
// TODO: See if we can relax this.
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

// -----

// Rejection of select-like ops that use values subject to linearity.

func.func private @make_qubit() -> !prelimhlep.lin<i1>

func.func private @select_between_linear_values(%cond: i1, %v: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    attributes { prelimhlep.halo = #prelimhlep.halo } {
    %u = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
    // expected-error @below {{'prelimhlep.halo' function uses a value subject to linearity as an operand or result of a select-like op; only one of a select's operands is ever actually produced, but both must exist unconditionally, so this analysis cannot prove the other one isn't silently discarded}}
    %r = arith.select %cond, %v, %u : !prelimhlep.lin<i1>
    return %r : !prelimhlep.lin<i1>
}

// -----

func.func private @make_register() -> !prelimhlep.lin<i4>

// The loop body drops the carried register and yields a fresh one instead.
func.func private @loop_drops_carried_value(%state : !prelimhlep.lin<i4>) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    // expected-error @below {{'prelimhlep.halo' block argument #1 is subject to linearity, but is never used}}
    %out = scf.for %i = %c0 to %c4 step %c1 iter_args(%reg = %state) -> (!prelimhlep.lin<i4>) {
        %fresh = func.call @make_register() : () -> !prelimhlep.lin<i4>
        scf.yield %fresh : !prelimhlep.lin<i4>
    }
    return %out : !prelimhlep.lin<i4>
}

// -----

func.func private @extract_4(!prelimhlep.lin<i4>, index) -> (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo }
func.func private @insert_4(!prelimhlep.lin<i3>, !prelimhlep.lin<i1>, index) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo }
func.func private @make_qubit() -> !prelimhlep.lin<i1>

// The extracted qubit is dropped, and a fresh qubit is inserted in its place.
func.func private @loop_drops_extracted_qubit(%state : !prelimhlep.lin<i4>) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    %out = scf.for %i = %c0 to %c4 step %c1 iter_args(%reg = %state) -> (!prelimhlep.lin<i4>) {
        // expected-error @below {{'prelimhlep.halo' result #1 of 'func.call' is subject to linearity, but is never used}}
        %rest, %qubit = func.call @extract_4(%reg, %i) : (!prelimhlep.lin<i4>, index) -> (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>)
        %fresh = func.call @make_qubit() : () -> !prelimhlep.lin<i1>
        %next = func.call @insert_4(%rest, %fresh, %i) : (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>, index) -> !prelimhlep.lin<i4>
        scf.yield %next : !prelimhlep.lin<i4>
    }
    return %out : !prelimhlep.lin<i4>
}

// -----

func.func private @extract_4(!prelimhlep.lin<i4>, index) -> (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo }
func.func private @insert_4(!prelimhlep.lin<i3>, !prelimhlep.lin<i1>, index) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo }
func.func private @consume_register(!prelimhlep.lin<i4>) -> ()

// The carried register is extracted from twice in the same iteration.
func.func private @loop_extracts_twice(%state : !prelimhlep.lin<i4>) -> !prelimhlep.lin<i4> attributes { prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    %out = scf.for %i = %c0 to %c4 step %c1 iter_args(%reg = %state) -> (!prelimhlep.lin<i4>) {
        // expected-error @below {{'prelimhlep.halo' block argument #1 is subject to linearity, but is used more than once}}
        // expected-note @below {{used here}}
        %rest, %qubit = func.call @extract_4(%reg, %i) : (!prelimhlep.lin<i4>, index) -> (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>)
        // expected-note @below {{used here}}
        %rest_again, %qubit_again = func.call @extract_4(%reg, %i) : (!prelimhlep.lin<i4>, index) -> (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>)
        %next = func.call @insert_4(%rest, %qubit, %i) : (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>, index) -> !prelimhlep.lin<i4>
        %next_again = func.call @insert_4(%rest_again, %qubit_again, %i) : (!prelimhlep.lin<i3>, !prelimhlep.lin<i1>, index) -> !prelimhlep.lin<i4>
        func.call @consume_register(%next_again) : (!prelimhlep.lin<i4>) -> ()
        scf.yield %next : !prelimhlep.lin<i4>
    }
    return %out : !prelimhlep.lin<i4>
}

// -----

// The register carried out of the loop is never used.
func.func private @loop_result_dropped(%state : !prelimhlep.lin<i4>) -> !prelimhlep.unit attributes { prelimhlep.halo } {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    // expected-error @below {{'prelimhlep.halo' result #0 of 'scf.for' is subject to linearity, but is never used}}
    %out = scf.for %i = %c0 to %c4 step %c1 iter_args(%reg = %state) -> (!prelimhlep.lin<i4>) {
        scf.yield %reg : !prelimhlep.lin<i4>
    }
    %unit = prelimhlep.unit_value : !prelimhlep.unit
    return %unit : !prelimhlep.unit
}
