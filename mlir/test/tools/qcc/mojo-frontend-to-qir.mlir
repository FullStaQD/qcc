// The Mojo frontend all the way to an artifact: elaborated Mojo residue in,
// QIR out, in one `qcc` invocation.
//
// `--compile-to=mlir` still stops at QCO, which is what the PrelimHLEP lit
// tests check. Anything further runs `buildQCOLoweringPipeline`, which makes
// the QCO program fit the target's qubit model and hands it to the target's
// own passes.
//
// The input is the module of `tools/qcc-opt/mojo-residue-pipeline-test.mlir`,
// captured from `mojo/spikes/s2pipeline.mojo`; it is repeated here rather than
// shared so that this file is a self-contained `qcc` test and does not depend
// on another test's fixture. `test/mojo/grover.test` is the version driven by
// the fork's `kgen`.

// RUN: qcc --frontend=mojo-ir --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-QCO
// RUN: qcc --frontend=mojo-ir --compile-to=llvmir %s | FileCheck %s --check-prefix=CHECK-QIR

// The QCO stage is unchanged by the target lowering existing.
// CHECK-QCO-LABEL: func.func @flip() -> i1
// CHECK-QCO-SAME:    qcc.entry_point
// CHECK-QCO:         qco.alloc
// CHECK-QCO:         qco.x
// CHECK-QCO:         qco.measure
// CHECK-QCO-NOT:     prelimhlep

// `@export("flip")` is what makes the function an entry point; there is no
// `@main` here, so nothing depends on the JASP path's naming convention.
// CHECK-QIR: define void @flip()
// CHECK-QIR: call void @__quantum__rt__initialize
// CHECK-QIR: call void @__quantum__qis__x__body
// CHECK-QIR: call void @__quantum__qis__mz__body
// CHECK-QIR: call void @__quantum__rt__bool_record_output
// CHECK-QIR: ret void

"builtin.module"() ({
  "kgen.func"() <{LLVMArgMetadata = [], LLVMMetadata = {}, crossDeviceCaptures = #M<strings[]>, decorators = #kgen<decorators[]>, exportKind = #kgen.export<exported>, funcTypeGenerator = !kgen.generator<() cabi -> !kgen.scalar<bool>>, inlineLevel = 0 : i32, sym_name = "flip"}> ({
    %0 = "kgen.param.constant"() <{value = false}> : () -> i1
    %1 = "kgen.param.constant"() <{value = #kgen<simd true> : !kgen.scalar<bool>}> : () -> !kgen.scalar<bool>
    %2 = "prelimhlep.lin"() ({
      "prelimhlep.output"(%0) <{operandSegmentSizes = array<i32: 1, 0>}> : (i1) -> ()
    }) : () -> !prelimhlep.lin<i1>
    %3 = "prelimhlep.lin"(%2) ({
    ^bb0(%arg1: i1):
      %6 = "pop.cast_from_builtin"(%arg1) : (i1) -> !kgen.scalar<bool>
      %7 = "pop.simd.xor"(%6, %1) : (!kgen.scalar<bool>, !kgen.scalar<bool>) -> !kgen.scalar<bool>
      %8 = "pop.cast_to_builtin"(%7) : (!kgen.scalar<bool>) -> i1
      "prelimhlep.output"(%8) <{operandSegmentSizes = array<i32: 1, 0>}> : (i1) -> ()
    }) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    %4 = "prelimhlep.lin"(%3) ({
    ^bb0(%arg0: i1):
      "prelimhlep.output"(%arg0) <{operandSegmentSizes = array<i32: 0, 1>}> : (i1) -> ()
    }) : (!prelimhlep.lin<i1>) -> i1
    %5 = "pop.cast_from_builtin"(%4) : (i1) -> !kgen.scalar<bool>
    "kgen.return"(%5) : (!kgen.scalar<bool>) -> ()
  }) : () -> ()
}) : () -> ()
