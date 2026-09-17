# Mojo frontend

A Mojo-embedded language for PrelimHLEP, compiled by qcc. See
`mojo-frontend.md` at the repo root for the design and the phase plan.

## Layout

- `hlep/hlep.mojo` — the eDSL: `Lin`, `Reg4`, `Quad`, `Halo` and the
  primitive gates, written in raw inline MLIR. Users compose primitives with
  plain calls.
- `kernels/` — kernels written against it. `grover.mojo` is the Mojo version
  of `mlir/test/tools/qcc-opt/prelim-hlep-to-qco-grover-test.mlir` and lowers
  to the same circuit; `kernels/errors/` holds one rejected program per rule
  owner.
- `spikes/` — the phase 0/1/2 spikes, and the captured elaborator output the
  qcc importer's fixtures are made of.
- `patches/` — a pointer to the fork branch carrying the compiler changes.
- `dialect-sync/` — the manifest, sync script and round-trip check that keep
  the fork's copy of the PrelimHLEP dialect equal to this one.

## The chain

```
mojo source
  -> kgen --elaborate -O1 -I <repo>/mojo/hlep --emit-quantum-kernels=DIR
  -> qcc --frontend=mojo-ir --compile-to=mlir DIR/<kernel>.mlir
```

`kgen --emit-quantum-kernels` writes one generic-form module per exported
quantum kernel: that function plus everything it calls, with locations.
`qcc --frontend=mojo-ir` reads one, translates the Mojo residue
(`--mojo-residue-to-std`), inlines, and lowers the PrelimHLEP program to QCO.
It stops there for now, because the lowering from QCO to a target does not
exist yet; `--compile-to` must therefore be `mlir`.

The same chain by hand, one pass at a time:

```
qcc-opt --allow-unregistered-dialect --mlir-very-unsafe-disable-verifier-on-parsing \
        --mojo-residue-to-std --inline \
        --prelim-hlep-normalize-lin --prelim-hlep-to-qco --canonicalize
```

The two parser flags are the import configuration, not a workaround for
broken input: Mojo emits `kgen`/`pop`/`hlcf` ops qcc does not know, and the
module is not a well-formed PrelimHLEP program until `--mojo-residue-to-std`
has run. The `prelimhlep` ops themselves are registered on both sides and
parse with their real syntax.

## Who reports what

Every rule has one owner, and the diagnostic comes from that owner at the
Mojo line it belongs to. `mlir/test/mojo/kernel-errors-{mojo,qcc}.test` is
one program per row:

| Rule                                    | Owner            | Example                            |
| --------------------------------------- | ---------------- | ---------------------------------- |
| A qubit is used once                    | Mojo             | `kernels/errors/double.mojo`       |
| A qubit is not dropped                  | Mojo             | `kernels/errors/drop.mojo`         |
| A body has no early exit                | Mojo's parser    | `kernels/errors/early_return.mojo` |
| A body's results leave through `output` | the residue pass | `kernels/errors/leak.mojo`         |
| Quantum semantics                       | qcc's verifiers  | `kernels/errors/bad_basis.mojo`    |

## Writing a kernel

Two shapes that are not obvious from the library, both forced by Mojo rather
than chosen:

- **A gate with several qubits in and out takes them `mut`** and writes them
  back (`cx`), because a linear value cannot be moved out of a Mojo tuple or
  out of the middle of a struct. Such a gate must be `@always_inline`: a
  `mut` parameter is a pointer, and Mem2Reg cannot promote a qubit passed
  through one.
- **A value assigned inside a body may not be read after it.** Move it into
  a local before the region if the body is going to write it (see `cx`), or
  send it out through `prelimhlep.output`.

## Status

Phase 2 is done.

- `hlep/hlep.mojo` is rewritten and compiles; `kernels/grover.mojo` lowers to
  the same QCO circuit as the MLIR Grover test, driven by
  `kgen --emit-quantum-kernels` and then `qcc --frontend=mojo-ir`.
- The importer's fixtures under `mlir/test/tools/qcc-opt/mojo-residue-*.mlir`
  are captured elaborator output, not hand-written imitations of it, except
  the negative ones.
- The fork gained `var` inside a `__mlir_region` body, Mem2Reg through one,
  `--emit-quantum-kernels`, and the registered `complex` dialect that
  `prelimhlep.scale`'s factor is written with.

Still open, for phase 3 and later: qcc is driven by hand rather than by the
Mojo compiler (F9), there is no runtime or launcher, loops in a body are
`hlcf.loop` and not yet in the residue table, and `Lin` is monomorphic
because a `__mlir_region` block argument cannot be typed by a parameter.
