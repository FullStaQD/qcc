"""A dropped qubit: Mojo's rule, reported by Mojo at the Mojo line.

Linearity is not checked by qcc first and Mojo second. `Lin` is not
`Deinitable`, so there is no code path that drops one.
"""

from hlep import make_qubit, measure


@export("drop")
def drop() abi("C") -> Bool:
    var q = make_qubit()
    var dropped = make_qubit()
    return measure(q^)
