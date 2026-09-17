#!/usr/bin/env python3
"""Copies the shared PrelimHLEP dialect definition from qcc into the Mojo fork.

qcc is the source of truth. The fork holds a stamped copy: alongside the copied
files, 'sync.py' writes a 'QCC_SYNC' stamp recording the qcc commit it copied
from and a SHA-256 per file. Two tests read that stamp -- one in the fork,
checking its copies still hash to what the stamp says, and one in 'check-qcc'
(gated on the CMake cache variable 'QCC_MOJO_FORK'), checking the stamp still
matches what qcc has today.

    sync.py --fork /home/vscode/external/modular            # copy and stamp
    sync.py --fork /home/vscode/external/modular --check    # report drift only
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

QCC_ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).resolve().parent / "MANIFEST"
STAMP = "Mojo/lib/PrelimHLEPDialect/QCC_SYNC"
STAMP_HEADER = "# Written by mojo/dialect-sync/sync.py. Do not edit by hand."


def read_manifest() -> list[tuple[str, str]]:
    entries = []
    for lineno, raw in enumerate(MANIFEST.read_text().splitlines(), start=1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if "->" not in line:
            sys.exit(f"{MANIFEST}:{lineno}: expected '<source> -> <destination>'")
        source, destination = (part.strip() for part in line.split("->", 1))
        entries.append((source, destination))
    if not entries:
        sys.exit(f"{MANIFEST}: no entries")
    return entries


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def qcc_commit() -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(QCC_ROOT), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return "unknown"
    commit = result.stdout.strip()
    dirty = subprocess.run(
        ["git", "-C", str(QCC_ROOT), "status", "--porcelain", "--untracked-files=no"],
        capture_output=True,
        text=True,
    ).stdout.strip()
    return commit + ("-dirty" if dirty else "")


def read_stamp(path: Path) -> dict[str, str]:
    """Parses a 'QCC_SYNC' stamp into {destination path: sha256}."""
    stamped = {}
    if not path.is_file():
        return stamped
    for raw in path.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or line.startswith("qcc-commit "):
            continue
        sha, _, destination = line.partition("  ")
        if sha and destination:
            stamped[destination] = sha
    return stamped


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fork", required=True, type=Path, help="root of the Mojo fork checkout")
    parser.add_argument("--check", action="store_true", help="report drift without writing anything")
    args = parser.parse_args()

    fork = args.fork.resolve()
    if not (fork / "Mojo" / "BUILD.bazel").is_file():
        sys.exit(f"{fork}: does not look like a Mojo fork checkout (no Mojo/BUILD.bazel)")

    entries = read_manifest()
    stamped = read_stamp(fork / STAMP)
    problems = []
    digests = {}

    for source, destination in entries:
        source_path = QCC_ROOT / source
        destination_path = fork / destination
        if not source_path.is_file():
            sys.exit(f"{source}: listed in MANIFEST but missing from qcc")
        digests[destination] = digest(source_path)

        if args.check:
            if not destination_path.is_file():
                problems.append(f"{destination}: missing from the fork")
            elif digest(destination_path) != digests[destination]:
                problems.append(f"{destination}: differs from qcc's {source}")
            elif stamped.get(destination) != digests[destination]:
                problems.append(f"{destination}: matches qcc but the QCC_SYNC stamp is stale")
            continue

        destination_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source_path, destination_path)
        print(f"{source} -> {destination}")

    if args.check:
        for destination in stamped:
            if destination not in digests:
                problems.append(f"{destination}: stamped but no longer in MANIFEST")
        if problems:
            print("the fork's copy of the PrelimHLEP dialect has drifted:", file=sys.stderr)
            for problem in problems:
                print(f"  {problem}", file=sys.stderr)
            print(f"\nre-sync with: {Path(__file__).name} --fork {fork}", file=sys.stderr)
            return 1
        print("in sync")
        return 0

    stamp_path = fork / STAMP
    stamp_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [STAMP_HEADER, f"qcc-commit {qcc_commit()}"]
    lines += [f"{digests[destination]}  {destination}" for _, destination in entries]
    stamp_path.write_text("\n".join(lines) + "\n")
    print(f"stamped {STAMP}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
