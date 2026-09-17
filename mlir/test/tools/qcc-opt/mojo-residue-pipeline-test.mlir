// RUN: qcc-opt %s --allow-unregistered-dialect --mlir-very-unsafe-disable-verifier-on-parsing \
// RUN:   --mojo-residue-to-std --inline \
// RUN:   --prelim-hlep-normalize-lin --prelim-hlep-to-qco --canonicalize | FileCheck %s

// The import chain, end to end: elaborated Mojo residue in, QCO out, with
// nothing between `--mojo-residue-to-std` and the existing PrelimHLEP
// pipeline.
//
// Captured from `mojo/spikes/s2pipeline.mojo` with `kgen --elaborate -S -O1
// -mlir-print-op-generic`, module attribute dictionary removed. The whole
// kernel is one exported function here because the eDSL's gates are inlined
// during elaboration; `test/mojo/grover.test` is the version that goes
// through several.

// CHECK-LABEL: func.func @flip() -> i1
// CHECK:         %[[Q:.*]] = qco.alloc
// CHECK:         %[[X:.*]] = qco.x %[[Q]]
// CHECK:         %[[QO:.*]], %[[R:.*]] = qco.measure %[[X]]
// CHECK:         qco.sink %[[QO]]
// CHECK:         return %[[R]] : i1
// CHECK-NOT:     prelimhlep

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
