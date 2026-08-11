#!/usr/bin/env -S uv run --script --quiet

#  ===----------------------------------------------------------------------===//
#
#  Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
#  Exceptions.
#  See <repo-root>/LICENSE.txt for license information.
#  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
#  ===----------------------------------------------------------------------===//

# /// script
# dependencies = [
#   "qrisp[xdsl]==0.9.6",
# ]
# ///

"""
Generate MLIR (in the ``jasp`` dialect) from a Qrisp source file.

Usage::

    ./generate_qrisp_mlir.py <path-to-qrisp-file>

The Qrisp file should contain a single function (besides imports). This
function is run through ``qrisp.jasp.make_jaspr`` and the resulting MLIR is
printed to stdout, prefixed with a comment recording the installed Qrisp
version.
"""

import importlib.util
import inspect
import io
import subprocess
import sys
from contextlib import redirect_stdout

from qrisp.jasp import make_jaspr


def _load_module_from_path(path: str):
    """Load a Python source file as a module."""
    spec = importlib.util.spec_from_file_location("qrisp_source", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load module from path: {path}")
    module = importlib.util.module_from_spec(spec)
    with redirect_stdout(io.StringIO()):
        spec.loader.exec_module(module)
    return module


def _find_qrisp_function(module):
    """Find the single user-defined function in module."""
    candidates = [
        obj for name, obj in vars(module).items()
        if inspect.isfunction(obj)
        and not name.startswith("__")
        and getattr(obj, "__module__", None) == module.__name__
    ]

    if len(candidates) != 1:
        raise RuntimeError(
            "The file should contain a single function to convert."
        )
    return candidates[0]


def _to_selective_generic_mlir(module) -> str:
    """Serialize an xDSL module with only ``jasp`` ops in generic form.

    Rationale: custom jasp assembly has shown to be inconsistent between MLIR
    and xdsl (qrisp has to duplicate dialect definitions). Well-known standard
    dialects are still printed in custom assembly form for readability.
    """
    from io import StringIO

    from xdsl.context import Context
    from xdsl.dialects import arith, builtin, func, linalg, math, scf, tensor
    from xdsl.parser import Parser
    from xdsl.printer import Printer

    # Print to buffer in generic format.
    buf = StringIO()
    Printer(stream=buf, print_generic_format=True).print_op(module)

    # Load dialects we do not want to see in generic format in the reparsed
    # string below. Do not include jasp.
    ctx = Context()
    ctx.allow_unregistered = True
    for dialect in (
        builtin.Builtin,
        func.Func,
        arith.Arith,
        tensor.Tensor,
        scf.Scf,
        linalg.Linalg,
        math.Math,
    ):
        ctx.load_dialect(dialect)

    reparsed = Parser(ctx, buf.getvalue()).parse_module()
    return str(reparsed)


def _get_qrisp_version() -> str:
    """Return the installed Qrisp version as reported by ``uv pip freeze``."""
    try:
        result = subprocess.run(
            ["uv", "pip", "freeze"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "unknown"

    for line in result.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("qrisp==") or stripped.startswith("qrisp @"):
            return stripped[7:]
    return "unknown"


def main(argv):
    if len(argv) != 2:
        print(
            f"Usage: {argv[0]} <path-to-qrisp-file>",
            file=sys.stderr,
        )
        return 1

    path = argv[1]
    source_module = _load_module_from_path(path)
    qrisp_function = _find_qrisp_function(source_module)
    qrisp_version = _get_qrisp_version()

    mlir_module = make_jaspr(qrisp_function)().to_mlir(lower_stablehlo=True)
    mlir = _to_selective_generic_mlir(mlir_module)

    print(
        f"// GENERATED FROM QRISP VERSION {qrisp_version}\n\n"
        f"{mlir}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
