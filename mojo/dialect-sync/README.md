# Sharing the PrelimHLEP dialect with the Mojo fork

The Mojo fork registers the `prelimhlep` dialect so that kernels are parsed,
typed and elaborated inside Mojo's own pipeline. Its definition is generated
from the same TableGen qcc uses, and its custom parsers and printers are the
same C++.

**qcc is the source of truth. The fork holds a stamped copy.** A change to a
shared file is a qcc change; the same working session runs `sync.py` and
commits the fork with a message citing the qcc commit. A qcc change that needs
new C++ in the fork -- a new op with a verifier, a new attribute with custom
syntax -- adds the stub or the syntax in the same pair of commits.

## Files

- [`MANIFEST`](MANIFEST) -- what is shared, and where it lands in the fork.
- [`sync.py`](sync.py) -- copies the manifest files and writes the
  `QCC_SYNC` stamp (qcc commit + SHA-256 per file).
  `--check` reports drift without writing.
- [`roundtrip.py`](roundtrip.py) and [`roundtrip/`](roundtrip/) -- runs a
  corpus of PrelimHLEP syntax through `qcc-opt` and the fork's `kgen-opt` and
  requires the two generic-form prints to be byte-identical.

```bash
python3 mojo/dialect-sync/sync.py --fork /home/vscode/external/modular
python3 mojo/dialect-sync/sync.py --fork /home/vscode/external/modular --check
```

## The three tests

| Test                                    | Where       | Fails when                                                      |
| --------------------------------------- | ----------- | --------------------------------------------------------------- |
| `//Mojo/test/prelimhlep:dialect_sync`   | fork        | Someone edited the fork's copy in place. Needs no qcc checkout. |
| `mlir/test/mojo/dialect-sync.test`      | `check-qcc` | qcc changed the dialect and the fork has not been re-synced.    |
| `mlir/test/mojo/dialect-roundtrip.test` | `check-qcc` | The two compilers print PrelimHLEP syntax differently.          |

The two `check-qcc` tests are gated on the CMake cache variable
`QCC_MOJO_FORK`, and are reported unsupported when it is unset, so CI without a
fork checkout stays green:

```bash
cmake -S . -B build/julian-dev -DQCC_MOJO_FORK=/home/vscode/external/modular
```

The round-trip test also needs the fork's `kgen-opt`
(`./bazelw build --config=build-mojo //Mojo/tools/kgen-opt`); CMake warns and
skips the test if it is not built.

## What is not shared

Verifiers, `LinShapes.*`, `LinearityChecker.cpp` and every pass stay in qcc.
Quantum semantics are checked once, by qcc, in the subprocess that compiles the
extracted kernel module. The fork's
`Mojo/lib/PrelimHLEPDialect/PrelimHLEPVerifiersStub.cpp` supplies empty bodies
for the verifiers ODS declares; adding a verifier in qcc breaks the fork's
build until a stub joins it, which is the intended loud failure.

Constraints on the shared set: the `.td` files use only ODS features present in
both LLVMs (qcc builds against `llvmorg-23.1.0`, the fork against Modular's
`a033a30d`), and `PrelimHLEPSyntax.cpp` uses only the stable
`OpAsmParser`/`OpAsmPrinter`/`AsmParser`/`AsmPrinter` API. Both are checked by
building.

## Round-trip corpus

The fork does not register the `func` dialect, so qcc's own `prelimhlep` lit
inputs -- which wrap everything in `func.func` -- cannot be fed to `kgen-opt`
as they stand. The corpus in [`roundtrip/`](roundtrip/) is purpose-built
instead: bare `prelimhlep` ops at module scope, covering every construct with a
hand-written parser or printer. It is run together with
`mojo/spikes/cx-generic.mlir`, the captured elaborator output, which is what
actually crosses between the two compilers.
