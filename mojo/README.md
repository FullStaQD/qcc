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
  -> qcc --frontend=mojo-ir DIR/<kernel>.mlir
```

`kgen --emit-quantum-kernels` writes one generic-form module per exported
quantum kernel: that function plus everything it calls, with locations.
`qcc --frontend=mojo-ir` reads one, translates the Mojo residue
(`--mojo-residue-to-std`), inlines, and lowers the PrelimHLEP program to QCO.

From QCO it continues into the selected `--target`, so the chain now produces
an artifact rather than stopping at MLIR. `--compile-to=mlir` still stops at
QCO, which is what the PrelimHLEP lit tests check; `--compile-to=llvmir` (the
default) and `--compile-to=native` run the target's lowering.

Between QCO and the target sits `buildQCOLoweringPipeline`, which makes the
program fit the model the backends have of a machine -- a fixed register file
of qubits, acted on by one- and two-qubit gates:

- `decompose-multi-controlled` (mqt-core) rewrites a wider controlled gate,
  such as Grover's three-control Z, into elementary ones.
- `qco-assign-static-qubits` replaces `qco.alloc` with `qco.static <index>`,
  because `qc.alloc` is illegal in the QIR lowering. Indices are handed out
  module-wide and never reused; a liveness-based allocator would be a separate
  pass, and needs the target's qubit count to be worth running.
- `qco-to-qc` (mqt-core) crosses from QCO's linear value semantics to QC's
  references, which is where `Target::addLoweringPasses` picks the module up.
- `symbol-dce` drops private helpers nothing calls, which the QIR lowering
  cannot lower because their qubits arrive as function arguments.

The entry point is whichever function carries `qcc.entry_point`, which
`--mojo-residue-to-std` sets on every `@export`ed kernel. The JASP path's
`add-entrypoint-to-main` is not used here: a Mojo kernel is named after its
`@export`, and there is no `@main` to find.

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

## The driver contract

`qcc --frontend=mojo-ir` is meant to be run by a compiler, not only by a
person, so beside the text diagnostics and the artifact on stdout there is a
machine-readable surface. `mlir/test/tools/qcc/mojo-frontend-protocol.mlir`
and `mojo-frontend-diagnostics-json.mlir` are what it promises.

| Flag                       | What it does                                                                                                                                                    |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--protocol=N`             | The caller states the contract version it was built against. qcc speaks 1 and refuses anything else, before reading the input. Omitting it skips the handshake. |
| `--diagnostics=json`       | Diagnostics on stderr as one JSON object per line instead of source-and-caret.                                                                                  |
| `--emit-entry-points=FILE` | Writes the entry-point sidecar, as JSON.                                                                                                                        |
| `--verify-only`            | Translates and verifies, then stops: no lowering, no artifact.                                                                                                  |

The Mojo path runs in two stages, and what sits between them is what the
contract is written in terms of: a verified PrelimHLEP program whose functions
still carry the signatures the caller wrote. `--verify-only` stops there, and
the sidecar is taken from there rather than from the lowered module, whose
signatures belong to the target.

A diagnostic record has `severity` and `message`, plus `file`, `line` and
`column` when the location names them — a location qcc cannot resolve leaves
them out rather than inventing a position. Attached notes and the callers of
an inlined callsite become `notes`, each of the same shape. One object per
line is what lets the caller relay a diagnostic as it arrives rather than at
exit. The positions are Mojo's own, because Mojo's locations are.

The sidecar names each `@export`ed kernel and the signature a launcher is
typed from:

```json
{
  "protocol": 1,
  "entry_points": [
    { "name": "flip", "halo": true, "arguments": [], "results": ["i1"] }
  ]
}
```

`!prelimhlep.unit` is left out of those signatures. It is qcc's own token —
the halo verifier wants a haloed function to name the state it acts on, and
the residue translation synthesizes one for a kernel with no classical
arguments — so the caller has nothing to pass for it. That the kernel is a
quantum one is said once, by `halo`.

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

Phase 3 has started. The QCO entry into target lowering is built, so
`qcc --frontend=mojo-ir` compiles a kernel to QIR in one invocation; see "The
chain" above. Getting there needed three things the plan did not predict:

- mqt-core had to be bumped (to `b897f04b`), because the `qco-to-qc` bridge
  did not compile against qcc's LLVM, which has dropped the deprecated
  `llvm::make_scope_exit`. The bump moved mqt's include prefix from `mlir/` to
  `mqt/` across the repo, and brought `decompose-multi-controlled`, without
  which no Grover-shaped kernel reaches a target at all.
- `aux.record_int` lowered only `i1` and `i64`. A Mojo kernel returning a
  packed register returns an `i4`, so the QIR lowering now zero-extends any
  integer narrower than the runtime function's `i64`.
- `qco.id` gained a folder upstream, so it can no longer reach a conversion
  pattern through the driver; `convert-qco-to-qvec.mlir` says so where it used
  to test that it converts.

The protocol surface is built too; see "The driver contract" above.

Still open, for the rest of phase 3 and later: F9's launch site so that `mojo build` drives qcc rather than a person, the
`qpu.host` runtime and a simulator backend, loops in a body (`hlcf.loop`, not
yet in the residue table), and `Lin` being monomorphic because a
`__mlir_region` block argument cannot be typed by a parameter.
