# Generation of Test Cases from Qrisp

This guide documents the process of converting a [Qrisp](https://qrisp.eu/) quantum program into an MLIR test case for `qcc`.

---

## Instructions

Generate MLIR in the `jasp` dialect:

```bash
mlir/utils/generate_qrisp_mlir.py my_program.py > my_program.mlir
# Alternatively replace corresponding content in existing mlir file.
```

Add or update `FileCheck` directives as usual. See existing tests for inspiration.

## Notes on qrisp programs

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

## Performance considerations for simulation

It is important that our test suite runs fast. Most tests run within a few
milliseconds. Longer running tests have to be justified. Some tests use
`qir-runner` to simulate the compiled program which can potentially take very
long. Hence keep your programs minimal and verify the runtime.
