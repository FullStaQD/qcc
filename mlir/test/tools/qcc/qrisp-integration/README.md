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

- returns exactly one integer, the result of one `measure(qv)` at the end of the program. The recorded integer is
  split into its bits, and `magic-runner` reports them as a single integer again. A program with several outputs
  would lose their grouping (there is no MAGIC counterpart of `qir/multi_output`).
- has no classical control flow that depends on a measurement (`q_cond`, feed-forward) and no reset. Python loops
  are fine: they are unrolled when the program is traced. Loops whose bounds are only known at run time are not
  (this rules out Qrisp's built-in `QFT`; `magic/qft.py` writes the loops out).
- uses the gates `x y z h s s_dg t t_dg rx ry rz p`, `cx cy cz cp rzz` only.
- should have a (nearly) deterministic outcome, so that the simulation can be checked: `magic/qft.py` prepares
  its input such that the QFT yields a basis state.

How the ions are distributed over the traps follows from the number of qubits and the capacities of the device: if
all fit into the first trap they go there, otherwise every trap is filled up to one free slot. Each test picks a
device from `magic/Inputs/` accordingly (e.g. three qubits on capacities 2 and 3 spread over both traps, which
needs shuttling).

## Simulating MAGIC programs

`--compile-to=custom-magic` writes the program in the text format the device takes today, and
`mlir/utils/magic-runner` simulates that text. It needs the device file as well, for the coupling strengths:

```bash
qcc my_program.mlir --quantum-device=magic --device-description=magic/Inputs/device-2x3.mlir \
    --compile-to=custom-magic -o my_program.txt
mlir/utils/magic-runner --file my_program.txt --device magic/Inputs/device-2x3.mlir -s 5
```

The output follows `qir-runner`: one `OUTPUT INT <n>` line per shot. `--probabilities` prints the exact
distribution instead. Bits that are no result of the program (the device measures every ion, see the pass
`magic-measure-and-record-garbage`) are dropped unless `--keep-garbage-bits` is given.

The script installs its dependency (numpy) on the first run and needs `uv`. In the tests it is available as
`magic-runner`; the test suite refuses to run without `uv`.

The text format has a fixed header. Its `include` line names a file of the device vendor's tooling; that name is
part of the format and the only place where it appears.

## Performance considerations for simulation

It is important that our test suite runs fast. Most tests run within a few
milliseconds. Longer running tests have to be justified. Some tests use
`qir-runner` or `magic-runner` to simulate the compiled program which can
potentially take very long. Hence keep your programs minimal and verify the
runtime.
