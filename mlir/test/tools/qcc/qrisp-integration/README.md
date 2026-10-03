# Integration Tests with Qrisp

End-to-end tests that start from a [Qrisp](https://qrisp.eu/) program: the program is converted to MLIR in the `jasp`
dialect once, checked in, and compiled by `qcc` in the test. Where a simulator is available the compiled program is
also run.

| Folder   | Compiled for                              | Simulator      |
| -------- | ----------------------------------------- | -------------- |
| `qir/`   | QIR                                       | `qir-runner`   |
| `magic/` | a MAGIC device (`--quantum-device=magic`) | `magic-runner` |

Each test consists of the Qrisp source `<name>.py` and the test `<name>.mlir` generated from it.

---

## Generating a test case

Generate MLIR in the `jasp` dialect:

```bash
mlir/utils/generate_qrisp_mlir.py my_program.py > my_program.mlir
# Alternatively replace corresponding content in existing mlir file.
```

The script installs Qrisp on the fly (it needs `uv`). Add or update the `RUN` lines and `FileCheck` directives as
usual. See existing tests for inspiration.

## Notes on Qrisp programs

Qrisp programs used to generate test cases should contain a single function definition. For example:

```python
from qrisp import QuantumVariable, h, cx, measure

def bell():
    qv = QuantumVariable(2)
    h(qv[0])
    cx(qv[0], qv[1])
    mes0 = measure(qv[0])
    mes1 = measure(qv[1])
    return
```

Do not use `jrange` or `with control(classical condition)`. Instead use `q_cond` or `q_fori_loop`.

### Additional rules for `magic/`

A MAGIC program is a fixed sequence of gates followed by the measurement of all ions. So a program for `magic/`

- ends with a single `measure(qv)` and returns its result,
- has no control flow that depends on a measurement or is only known at run time, and no reset,
- should have a (nearly) deterministic outcome, so that the simulation can be checked.

The tests simulate the compiled program with `mlir/utils/magic-runner` (see its `--help`), which needs `uv`.

## Performance considerations for simulation

It is important that our test suite runs fast. Most tests run within a few
milliseconds. Longer running tests have to be justified. Some tests use
`qir-runner` or `magic-runner` to simulate the compiled program which can
potentially take very long. Hence keep your programs minimal and verify the
runtime.
