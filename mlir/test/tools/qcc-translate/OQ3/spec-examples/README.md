Examples from the OpenQASM specification repository, <https://github.com/openqasm/openqasm>, directory `examples/`, at
commit 7fbf9e9eb3692a1288c014d6efd43523701886c6. They are licensed under the Apache License 2.0 (see `LICENSE`).

Each example is modified by a test header: a `RUN` line and the expected output of an import and export as `CHECK`
lines. The rest of the file is unchanged.

The OpenQASM importer is expected to handle all 22 examples eventually; this directory holds the ones it handles so
far.
