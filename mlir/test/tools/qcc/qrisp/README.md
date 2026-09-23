# From Qrisp to MLIR: Step-by-Step Guide

This guide documents the process of converting a [Qrisp](https://qrisp.eu/) quantum program into an MLIR input file suitable for FullStaQD compilation (e.g. with `qcc`).

---

## Prerequisites

This project requires a Python environment with `qrisp` installed. You can install it via pip:

```bash
pip install git+https://github.com/eclipse-qrisp/Qrisp.git@b81ea2f979d21cd8d600e79d8b0c7066fe7cbe1b
pip install xdsl==0.59.0
```

The above command is pinpointing to this a specific version of [Qrisp](https://github.com/eclipse-qrisp/Qrisp/pull/528) which mostly solved the dependencies from `stablehlo` dialect.

## **Troubleshooting**: If you encounter any problems, check the official [Qrisp setup documentation](https://qrisp.eu/general/setup.html) for detailed instructions.

## Step 1 — Write Your Qrisp Program

Start by writing your quantum algorithm as a standard Python function using the Qrisp API. For example:

```python
from qrisp import QuantumVariable, h, cx, measure
from qrisp.jasp import make_jaspr

def bell():
    qv = QuantumVariable(2)
    h(qv[0])
    cx(qv[0], qv[1])
    mes0 = measure(qv[0])
    mes1 = measure(qv[1])
    return

jaspr = make_jaspr(bell)()
print(jaspr.to_mlir(lower_stablehlo=True))
```

This example creates a bell state state and measures all the qubits.
Run the script:

```bash
python your_script.py
```

The output will be a block of MLIR text. Copy it — this is your **raw MLIR**, which will require a few manual transformations before it is ready to use.

---

## Step 2 — Add the `qcc.entry_point` Annotation

Locate the main function header in the MLIR output — it will look roughly like:

```mlir
func.func @main(...) -> ... {
```

Add the `attributes { qcc.entry_point }` annotation immediately after the function signature, before the opening brace:

```mlir
func.func @main(...) -> ... attributes { qcc.entry_point } {
```

---

## Remark

Despite this guide, remember to always document all manual tweaks you have to do to run any test correctly within `qcc` in a TODO comment within the tests themselves.
