// RUN: qcc-opt %s --allow-unregistered-dialect --mlir-very-unsafe-disable-verifier-on-parsing --mojo-residue-to-std --split-input-file --verify-diagnostics

// The residue table is closed on purpose: anything Mojo can emit that is not
// in it is reported here, at the Mojo source location, rather than reaching
// the PrelimHLEP verifiers as something they have no words for.
//
// Unlike the positive fixtures, these are written by hand: each is one op
// away from a program the table accepts, which is easier to state directly
// than to coax out of the elaborator. `test/mojo/kernel-errors-qcc.test`
// covers the same rules from real Mojo, with the Mojo line and column.

// Mem2Reg promotes a local away unless its value has to survive a boundary
// it cannot carry one across, and inside a kernel the only such boundary is
// a linearization body. So a memory op that reaches qcc is a variable
// written in a body and read after it.
"kgen.func"() <{sym_name = "leaking_assignment"}> ({
^bb0(%b: !kgen.scalar<bool>):
  // expected-error @+1 {{'pop.stack_allocation' is not supported in a quantum kernel: a value assigned inside a linearization body cannot be read after it; results leave a body through 'prelimhlep.output'}}
  %slot = "pop.stack_allocation"() : () -> !kgen.pointer<scalar<bool>>
  "kgen.return"() : () -> ()
}) : () -> ()

// -----

// A non-register-passable Mojo type never reaches a kernel signature, but if
// one did, the user learns which argument.
"kgen.func"() <{sym_name = "pointer_arg"}> ({
// expected-error @+1 {{argument type '!kgen.pointer<scalar<bool>>' is not supported in a quantum kernel}}
^bb0(%p: !kgen.pointer<scalar<bool>>):
  "kgen.return"() : () -> ()
}) : () -> ()

// -----

// Floating-point arithmetic inside a linearization body is not classical
// residue a quantum kernel can carry.
"kgen.func"() <{sym_name = "float_math"}> ({
^bb0(%a: !kgen.scalar<f64>, %b: !kgen.scalar<f64>):
  // expected-error @+1 {{only integer arithmetic is supported in a quantum kernel, got 'f64'}}
  %c = "pop.add"(%a, %b) : (!kgen.scalar<f64>, !kgen.scalar<f64>) -> !kgen.scalar<f64>
  "kgen.return"(%c) : (!kgen.scalar<f64>) -> ()
}) : () -> ()

// -----

// `hlcf.loop` is phase 4; until then a Mojo `while` or `for` in a kernel
// says so.
"kgen.func"() <{sym_name = "loop"}> ({
^bb0(%b: !kgen.scalar<bool>):
  // expected-error @+1 {{'hlcf.loop' is not supported in a quantum kernel}}
  "hlcf.loop"() ({
    "hlcf.break"() : () -> ()
  }) : () -> ()
  "kgen.return"() : () -> ()
}) : () -> ()

// -----

// Mojo returns several values as one struct, which this pass takes apart
// into the values its fields hold. A struct it cannot take apart -- because
// a field is outside the kernel vocabulary -- is reported rather than
// silently flattened wrong.
"kgen.func"() <{sym_name = "bad_struct_field"}> ({
^bb0(%p: !kgen.scalar<bool>):
  %s = "kgen.struct.create"(%p, %p) : (!kgen.scalar<bool>, !kgen.scalar<bool>) -> !kgen.struct<(scalar<bool>, pointer<scalar<bool>>)>
  // expected-error @+1 {{result type '!kgen.struct<(scalar<bool>, pointer<scalar<bool>>)>' is not supported in a quantum kernel}}
  "kgen.return"(%s) : (!kgen.struct<(scalar<bool>, pointer<scalar<bool>>)>) -> ()
}) : () -> ()

// -----

// A parametric struct index is one the elaborator did not resolve, which
// means the module is not the concrete kernel qcc was promised.
"kgen.func"() <{sym_name = "parametric_index"}> ({
^bb0(%p: !kgen.scalar<bool>):
  %s = "kgen.struct.create"(%p, %p) : (!kgen.scalar<bool>, !kgen.scalar<bool>) -> !kgen.struct<(scalar<bool>, scalar<bool>)>
  // expected-error @+1 {{'kgen.struct.extract' with a parametric index is not supported in a quantum kernel}}
  %f = "kgen.struct.extract"(%s) : (!kgen.struct<(scalar<bool>, scalar<bool>)>) -> !kgen.scalar<bool>
  "kgen.return"(%f) : (!kgen.scalar<bool>) -> ()
}) : () -> ()

// -----

// A Mojo constant this pass cannot read is not guessed at.
"kgen.func"() <{sym_name = "opaque_constant"}> ({
^bb0(%b: !kgen.scalar<bool>):
  // expected-error @+1 {{only integer constants are supported in a quantum kernel}}
  %c = "kgen.param.constant"() <{value = #kgen<dtype ui8>}> : () -> !kgen.scalar<ui8>
  "kgen.return"() : () -> ()
}) : () -> ()
