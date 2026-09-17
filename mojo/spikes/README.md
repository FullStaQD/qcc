# Phase 0/1 spikes

Run with the fork's `kgen` (branch `qcc-prelimhlep`, see `../patches/`). Since
phase 1 the `prelimhlep` dialect is registered in the fork, so
`--allow-unregistered-dialect` is no longer needed:

```bash
export MODULAR_MOJO_MAX_IMPORT_PATH=/home/vscode/external/modular/bazel-bin/Mojo/stdlib/std
KGEN=/home/vscode/external/modular/bazel-bin/Mojo/tools/kgen/kgen
$KGEN --elaborate -S -O1 -mlir-print-op-generic -mlir-print-debuginfo s1cx.mojo -o -
```

- `s1cx.mojo` — CNOT with a move of the target inside the linearization
  body. Compiles; this is the spike the whole "Mojo owns linearity" claim
  rests on.
- `s1double.mojo` — the same, using the target twice. Mojo rejects it:
  `error: use of uninitialized value 'target'`.
- `s1drop.mojo` — the same, dropping the target. Mojo rejects it with the
  library's own `@explicit_destroy` message.
- `s1generic.mojo` — `Lin[E]` over a parametric basis type, instantiated at
  `i1` and `i8`. Elaborates to concrete `!prelimhlep.lin<i1>` and
  `!prelimhlep.lin<i8>` with no `!kgen.param` left over: registering the
  dialect is what makes the elaborator's sub-element walk able to substitute
  into the type. Also records the one gap found doing so — a `__mlir_region`
  block argument cannot yet be typed by a parameter.
- `cx-generic.mlir` — the elaborated generic-form output of `s1cx.mojo`,
  captured from a real run. This is the contract the qcc importer's fixtures
  must match; qcc parses it as-is with `--allow-unregistered-dialect
--mlir-very-unsafe-disable-verifier-on-parsing`, and
  `../dialect-sync/roundtrip.py` checks that both compilers print it
  identically. Since phase 2's F8 it carries no memory ops: Mem2Reg promotes
  the reassigned target through the linearization body, so the `hlcf.if`
  yields the qubit rather than storing it.
- `s2residue.mojo`, `s2pipeline.mojo` — phase 2. The classical residue a
  kernel can carry, and the smallest whole kernel. Their elaborated output is
  what `mlir/test/tools/qcc-opt/mojo-residue-{test,pipeline-test}.mlir`
  contain; each file says how to re-capture it.

Since the dialect is registered, `prelimhlep.output` carries its real
`operandSegmentSizes` property, written from Mojo as
`_properties=__mlir_attr.`{operandSegmentSizes = array<i32: 1, 0>}``, rather
than the invented `carrying` attribute that an unregistered op accepted.

Phase 2 added `-I ../hlep` to the command line above: the spikes from
`s2residue.mojo` on import the eDSL library rather than restating it.
