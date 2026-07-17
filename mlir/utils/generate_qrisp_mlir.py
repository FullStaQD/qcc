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
#   "qrisp==0.9.5",
#   "xdsl==0.59.0"
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
    module = _load_module_from_path(path)
    qrisp_function = _find_qrisp_function(module)
    qrisp_version = _get_qrisp_version()

    mlir = str(make_jaspr(qrisp_function)().to_mlir(lower_stablehlo=True))

    print(
        f"// GENERATED FROM QRISP VERSION {qrisp_version}\n\n"
        f"{mlir}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
