// `--diagnostics=json` is the same diagnostics as the default rendering, in
// the form a frontend relays rather than the form a human reads: one JSON
// object per line on stderr, so the caller can forward each record as it
// arrives instead of waiting for qcc to exit, and stdout carries only the
// artifact.
//
// The locations here are the ones Mojo writes -- a `.mojo` file, with a
// `callsite` where the elaborator inlined a library gate -- so a record
// points at the kernel's own source rather than at the exchanged MLIR. The
// files do not have to exist: the text rendering reads them to quote the
// line, the JSON one only names them.

// RUN: not qcc --frontend=mojo-ir %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=CHECK-TEXT
// RUN: not qcc --frontend=mojo-ir --diagnostics=json %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=CHECK-JSON

"kgen.func"() <{sym_name = "kernel"}> ({
^bb0(%b: !kgen.scalar<bool>):
  %x = "pop.mystery"() : () -> !kgen.scalar<bool> loc(callsite("gate.mojo":7:3 at "kernel.mojo":12:9))
  "kgen.return"() : () -> () loc("kernel.mojo":13:1)
}) : () -> () loc("kernel.mojo":11:1)

// The callsite's callee is where the user is pointed; the callers above it
// become notes, in both renderings.
// CHECK-TEXT: gate.mojo:7:3: error: 'pop.mystery' is not supported in a quantum kernel
// CHECK-TEXT: kernel.mojo:12:9: note: called from

// CHECK-JSON: {"severity":"error","message":"'pop.mystery' is not supported in a quantum kernel","file":"gate.mojo","line":7,"column":3,"notes":[{"severity":"note","message":"called from here","file":"kernel.mojo","line":12,"column":9}
