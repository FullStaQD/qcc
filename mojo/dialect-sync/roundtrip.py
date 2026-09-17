#!/usr/bin/env python3
"""Checks that qcc and the Mojo fork agree, byte for byte, on PrelimHLEP syntax.

Each input is parsed and printed in generic form by both 'qcc-opt' (built
against llvmorg-23.1.0) and the fork's 'kgen-opt' (built against Modular's
LLVM). The two prints must be identical: that is what makes the textual
exchange between the two compilers one format rather than two that happen to
look alike.

Verification is off on both sides. What is under test is the shared parser and
printer ('PrelimHLEPSyntax.cpp'), not the semantics -- those are qcc's, and
qcc's own lit tests cover them.

    roundtrip.py --qcc-opt build/bin/qcc-opt --kgen-opt <fork>/bazel-bin/.../kgen-opt
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
QCC_ROOT = HERE.parents[1]

# The purpose-built corpus, plus the captured elaborator output: real Mojo
# residue around real prelimhlep ops, which is what actually crosses over.
DEFAULT_INPUTS = sorted((HERE / "roundtrip").glob("*.mlir")) + [QCC_ROOT / "mojo" / "spikes" / "cx-generic.mlir"]

QCC_FLAGS = [
    "--allow-unregistered-dialect",
    "--mlir-very-unsafe-disable-verifier-on-parsing",
    "--mlir-print-op-generic",
]
KGEN_FLAGS = ["--allow-unregistered-dialect", "--mlir-print-op-generic"]


def run(tool: Path, flags: list[str], source: Path) -> str:
    result = subprocess.run([str(tool), *flags, str(source)], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"{source}: {tool.name} failed:\n{result.stderr}")
    return result.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qcc-opt", required=True, type=Path)
    parser.add_argument("--kgen-opt", required=True, type=Path)
    parser.add_argument("inputs", nargs="*", type=Path, help="defaults to the corpus beside this script")
    args = parser.parse_args()

    inputs = args.inputs or DEFAULT_INPUTS
    if not inputs:
        raise SystemExit("no inputs")

    failures = 0
    for source in inputs:
        qcc_print = run(args.qcc_opt, QCC_FLAGS, source)
        # kgen-opt writes a crash-handler warning on startup in this container.
        kgen_print = run(args.kgen_opt, KGEN_FLAGS, source)
        if qcc_print == kgen_print:
            print(f"ok   {source.name}")
            continue

        failures += 1
        print(f"FAIL {source.name}: the two compilers print this differently", file=sys.stderr)
        import difflib

        diff = difflib.unified_diff(
            qcc_print.splitlines(keepends=True),
            kgen_print.splitlines(keepends=True),
            fromfile=f"{source.name} (qcc-opt)",
            tofile=f"{source.name} (kgen-opt)",
        )
        sys.stderr.writelines(diff)

    if failures:
        print(f"\n{failures} of {len(inputs)} inputs differ", file=sys.stderr)
        return 1
    print(f"{len(inputs)} inputs round-trip identically")
    return 0


if __name__ == "__main__":
    sys.exit(main())
