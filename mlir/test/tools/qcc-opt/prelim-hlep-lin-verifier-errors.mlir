// RUN: qcc-opt %s --split-input-file --verify-diagnostics

func.func @bad_arg_type(%q: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{body block argument #0 has type 'i64', expected the delinearized operand's element type 'i1'}}
    %0 = prelimhlep.lin (
        %b : i64 from %q : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i1>) {
        "prelimhlep.output"(%b) <{operandSegmentSizes = array<i32: 1, 0>}> : (i64) -> ()
    }
    return %0 : !prelimhlep.lin<i1>
}

// -----

func.func @bad_result_count(%q: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{expected 0 results to match the number of 'prelim_hlep.output' operands, got 1}}
    %0 = prelimhlep.lin (
        %b : i1 from %q : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i1>) {
        "prelimhlep.output"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> ()
    }
    return %0 : !prelimhlep.lin<i1>
}

// -----

func.func @bad_delinearized_result_type(%q: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i64> attributes { prelimhlep.halo = #prelimhlep.halo } {
    // expected-error @below {{result #0 has type '!prelimhlep.lin<i64>', expected the linearization of 'prelim_hlep.output' operand type 'i1'}}
    %0 = prelimhlep.lin (
        %b : i1 from %q : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i64>) {
        "prelimhlep.output"(%b) <{operandSegmentSizes = array<i32: 1, 0>}> : (i1) -> ()
    }
    return %0 : !prelimhlep.lin<i64>
}
