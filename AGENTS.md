# QCC

**qcc** is an MLIR-based compiler that lowers JASP dialect IR (produced by
[Qrisp](https://qrisp.eu)) to QIR. Generated tools: `qcc-opt` (an
`mlir-opt`-style pass explorer) and `qcc` (the end-to-end driver).

## Quick commands

Details and alternatives are in [README.md](README.md).

```shell
# Build (beware that the user might use a different preset)
cmake --preset dev                                  # configure
cmake --build build/dev                             # build

# Test (with dev preset)
cmake --build build/dev --target check-qcc          # build + run all tests
lit build/dev/mlir/test/ -v --filter NAME           # run a single/filtered test

# pre-commit checks
prek install                                        # to run on each commit
prek run -a                                         # autofixes too, might need a second run to pass
```

## Code style

Follow LLVM/MLIR conventions; Google's guidelines apply where LLVM is silent,
but LLVM always takes precedence. See [CONTRIBUTING.md](CONTRIBUTING.md) for
details, including the few exceptions where we deliberately deviate from LLVM.
