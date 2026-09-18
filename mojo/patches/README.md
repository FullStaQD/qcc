# Mojo compiler fork

The fork lives at `/home/vscode/external/modular` (the Bazel workspace root;
`Mojo/` is a subdirectory of it), on branch **`qcc-prelimhlep`**. Phase 1 is commit `0311c3e621`; the phase 2
changes (F7, F8 and the two rows below them) and F9 are on the branch as
well.

The changes used to be carried here as `inline-mlir-regions.patch`. They are
now commits on that branch: once the `prelimhlep` dialect is registered in the
fork, part of the change is a whole dialect library rather than a handful of
hunks, and the fork is a permanent product rather than a scratch tree.

```bash
cd /home/vscode/external/modular
git checkout qcc-prelimhlep
./bazelw build --config=build-mojo //Mojo/tools/kgen:kgen //Mojo/tools/kgen-opt //Mojo/stdlib/std
```

## What is on the branch

| Label | Files                                                                                                                                                                                                                                        | What it does                                                                                                                                                                                                                                                                                                                                                                         |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| F1    | `tools/kgen/kgen.cpp`                                                                                                                                                                                                                        | `-allow-unregistered-dialect` driver flag. Now a developer flag only: nothing on the product path needs it.                                                                                                                                                                                                                                                                          |
| F2    | `lib/MojoParser/ExprNodes.cpp`                                                                                                                                                                                                               | Only typo-check attributes against inherent names for a _registered_ op. An unregistered op declares none, so the check rejected every attribute on one.                                                                                                                                                                                                                             |
| F3    | `include/Mojo/LITDialect/OriginTrackable.h`, `lib/LITDialect/OriginTrackable.cpp`, `lib/LowerLIT/CheckLifetimes.cpp`                                                                                                                         | `OverallOpValueEffect::scopeOp` and its two handlers, so ownership and linearity are tracked _inside_ region bodies.                                                                                                                                                                                                                                                                 |
| F4    | `lib/LowerLIT/LowerSemanticCF.cpp`                                                                                                                                                                                                           | Lower a scope op's regions as fall-through scopes instead of asserting, and accept the body's own terminator at its end.                                                                                                                                                                                                                                                             |
| F5    | `lib/Transforms/SCCP.cpp`                                                                                                                                                                                                                    | Give an unknown region op's results an entry-state lattice value; a later use read an uninitialized element and asserted.                                                                                                                                                                                                                                                            |
| F6    | `include/Mojo/InlineScopeInterface/`, `lib/InlineScopeInterface/`, `include/Mojo/PrelimHLEPDialect/`, `lib/PrelimHLEPDialect/`, `include/qcc/`, `Mojo/BUILD.bazel`, `lib/ToolCommon/InitAllDialects/InitAllDialects.cpp`, `test/prelimhlep/` | The registered `prelimhlep` dialect, the verifier stubs, `InlineScopeOpInterface`, and the fork-side sync test.                                                                                                                                                                                                                                                                      |
| F7    | `lib/MojoParser/ParserStmts.cpp`                                                                                                                                                                                                             | Accept `var` inside a `__mlir_region` body. One line: the statement parser dispatched `var` to the pattern grammar only under an `FnOp`, although the expression-statement path three lines lower already accepted an `UnboundRegionOp` parent.                                                                                                                                      |
| F8    | `include/Mojo/TransformUtils/ControlFlowUtils.h`, `lib/TransformUtils/ControlFlowUtils.cpp`, `lib/Transforms/Mem2Reg.cpp`                                                                                                                    | Mem2Reg through an inline scope. `userCrossesFunctionCFG` gains an opt-in overload that passes through an `InlineScopeOpInterface` op and reports the scopes crossed; `canPromote` refuses an allocation written inside a scope and read outside it, and the rewrite walk opens a promotion scope for one so its writes do not escape.                                               |
| —     | `lib/ToolCommon/InitAllDialects/InitAllDialects.cpp`, `Mojo/BUILD.bazel`                                                                                                                                                                     | Register and preload MLIR's `complex` dialect: the eDSL writes `complex.constant` for the factor `prelimhlep.scale` takes, and registering it is what makes a malformed one a Mojo parse error.                                                                                                                                                                                      |
| —     | `tools/kgen/kgen.cpp`                                                                                                                                                                                                                        | `--emit-quantum-kernels=DIR`: write each exported quantum kernel, plus everything it calls, as a generic-form module with locations. This is the developer mode of F9 below: the same extraction, written out instead of handed over.                                                                                                                                                |
| F9    | `tools/kgen/QuantumKernels.{h,cpp}`, `tools/kgen/kgen.cpp`, `tools/kgen/BUILD.bazel`                                                                                                                                                         | `--qcc=PATH` (or `MOJO_QCC`) and `--qcc-target`: between elaboration and the CPU backend, run qcc on each extracted kernel, relay its JSON diagnostics through Mojo's diagnostic engine at the Mojo locations they name, embed the artifact as the `__qpu_artifact_<name>` accessors, and erase the haloed functions. See qcc's [`../README.md`](../README.md), "The caller's half". |

F3, F4, F6 and F8 key on `InlineScopeOpInterface`, a marker interface the
PrelimHLEP registration attaches to `prelimhlep.lin` from the outside, so the
shared TableGen names nothing Mojo-specific. Each of F3/F4 keeps the
unregistered-op branch beside it for development. F5 turned out to need no
re-keying: the fix is in a branch that already handles any op with regions.

## The shared dialect definition

`Mojo/include/qcc/Dialect/PrelimHLEP/IR/` and
`Mojo/lib/PrelimHLEPDialect/PrelimHLEPSyntax.cpp` are copied verbatim from this
repository by [`../dialect-sync/sync.py`](../dialect-sync/). Never edit them in
the fork; change them here and re-sync. Three tests watch the copy: see
[`../dialect-sync/README.md`](../dialect-sync/README.md).

## Regression status

`//Mojo/test/mojo-parser/...`, `//Mojo/test/kgen/...` and
`//Mojo/test/prelimhlep/...`: 581/581.
The full `//Mojo/test/...` was 966/1007 before this work, with all 41 failures
lldb tests failing on a missing `libncurses.so.6` in this container.
