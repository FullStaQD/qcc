"""A qubit used twice: Mojo's rule, reported by Mojo at the Mojo line.

`Lin` is not `Copyable`, so the second use reads a binding that the first
one ended.
"""

from hlep import cx, make_qubit, measure


@export("double")
def double() abi("C") -> Bool:
    var a = make_qubit()
    var b = make_qubit()
    cx(a, b)
    var first = measure(a^)
    var second = measure(a^)
    var third = measure(b^)
    return first and second and third
