// The machine-readable half of the fork-qcc contract: the version handshake,
// the entry-point sidecar, `--verify-only`, and diagnostics as JSON. These
// are what a frontend driving `qcc` as a subprocess talks to; a human uses
// the text diagnostics and the artifact on stdout.
//
// The input is the module of `tools/qcc-opt/mojo-residue-pipeline-test.mlir`,
// captured from `mojo/spikes/s2pipeline.mojo`, as in `mojo-frontend-to-qir.mlir`.

// The version the caller states is the version this build speaks, so the
// handshake is silent and compilation proceeds as usual.
// RUN: qcc --protocol=1 --frontend=mojo-ir --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-QCO

// A version qcc does not implement is refused before the input is read,
// rather than failing somewhere in the middle or producing an artifact the
// caller cannot read.
// RUN: not qcc --protocol=2 --frontend=mojo-ir %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=CHECK-PROTOCOL

// `--verify-only` runs the residue translation and the verifiers and stops:
// no artifact, and nothing on stdout. This is what the language server uses.
// RUN: qcc --frontend=mojo-ir --verify-only %s -o %t.out | FileCheck %s --check-prefix=CHECK-EMPTY --allow-empty
// RUN: not ls %t.out

// The sidecar is taken from between the two stages, where the module is a
// verified PrelimHLEP program whose functions still carry the signatures the
// caller wrote.
// RUN: qcc --frontend=mojo-ir --verify-only --emit-entry-points=%t.json %s
// RUN: FileCheck %s --check-prefix=CHECK-SIDECAR --input-file=%t.json

// CHECK-PROTOCOL: error: unsupported protocol version 2 (this qcc speaks 1)

// CHECK-EMPTY-NOT: {{.}}

// CHECK-SIDECAR:      "protocol": 1
// CHECK-SIDECAR:      "entry_points": [
// `@export("flip")` is the entry point; `halo` says it is a quantum one.
// CHECK-SIDECAR:        "name": "flip"
// CHECK-SIDECAR-NEXT:   "halo": true
// The `!prelimhlep.unit` argument the residue translation synthesizes for a
// kernel with no classical arguments is qcc's own token for the state a halo
// acts on. The caller never wrote it and has nothing to pass for it, so the
// signature it types a launcher from does not mention it.
// CHECK-SIDECAR-NEXT:   "arguments": []
// CHECK-SIDECAR:        "results": [
// CHECK-SIDECAR-NEXT:     "i1"

// The QCO stage is what it is without any of the above.
// CHECK-QCO-LABEL: func.func @flip() -> i1
// CHECK-QCO-SAME:    qcc.entry_point
// CHECK-QCO:         qco.measure
// CHECK-QCO-NOT:     prelimhlep

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
