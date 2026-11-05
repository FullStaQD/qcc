// RUN: qcc-opt %s --split-input-file --verify-diagnostics

func.func @bad_arg_type(%q: !hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo = #hlep.halo } {
    // expected-error @below {{body block argument #0 has type 'i64', expected the delinearized operand's element type 'i1'}}
    %0 = hlep.lin (
        %b : i64 from %q : !hlep.lin<i1>
    ) -> (!hlep.lin<i1>) {
        "hlep.output"(%b) <{operandSegmentSizes = array<i32: 1, 0>}> : (i64) -> ()
    }
    return %0 : !hlep.lin<i1>
}

// -----

func.func @bad_result_count(%q: !hlep.lin<i1>) -> !hlep.lin<i1> attributes { hlep.halo = #hlep.halo } {
    // expected-error @below {{expected 0 results to match the number of 'hlep.output' operands, got 1}}
    %0 = hlep.lin (
        %b : i1 from %q : !hlep.lin<i1>
    ) -> (!hlep.lin<i1>) {
        "hlep.output"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> ()
    }
    return %0 : !hlep.lin<i1>
}

// -----

func.func @bad_delinearized_result_type(%q: !hlep.lin<i1>) -> !hlep.lin<i64> attributes { hlep.halo = #hlep.halo } {
    // expected-error @below {{result #0 has type '!hlep.lin<i64>', expected the linearization of 'hlep.output' operand type 'i1'}}
    %0 = hlep.lin (
        %b : i1 from %q : !hlep.lin<i1>
    ) -> (!hlep.lin<i64>) {
        "hlep.output"(%b) <{operandSegmentSizes = array<i32: 1, 0>}> : (i1) -> ()
    }
    return %0 : !hlep.lin<i64>
}
