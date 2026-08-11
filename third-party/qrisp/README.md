# Qrisp Jasp Dialect

This directory contains the TableGen definition of the `jasp` dialect. It is
copied verbatim (aside from the modifications noted below) from the
[Qrisp](https://qrisp.eu) project, which is licensed under the Eclipse Public
License 2.0 (see [`LICENSE`](LICENSE)).

## Provenance

- **Upstream URL:** <https://github.com/eclipse-qrisp/Qrisp/tree/main/src/qrisp/jasp/mlir/dialect_definition>
- **Commit SHA:** `d011c5a361b287afce73f4ea70e5767f8df117a6`
- **Date copied:** `2026-08-06`
- **Files taken:** `JaspDialect.td`, `JaspOps.td`
- **Modified:** yes
  - Added include guards

## Upgrading

To upgrade, copy the upstream files over here again, re-apply the modifications listed
above, and update the provenance fields.

TODO: Agree on a single source of truth for the dialect definition.
See also issue <https://github.com/FullStaQD/compiler/issues/16>.

## Note: the dialect is defined twice upstream

Qrisp defines the dialect twice: on the one hand in the TableGen files mentioned above,
and on the other hand in xDSL (see e.g.
[`xdsl_dialect.py`](https://github.com/eclipse-qrisp/Qrisp/blob/main/src/qrisp/jasp/mlir/xdsl_dialect.py)).
The former is needed for JAX; the latter they use to implement passes in Python without
the full MLIR dependency.
