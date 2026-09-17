"""The classical residue a kernel can carry, in one file.

Elaborated and captured into
`mlir/test/tools/qcc-opt/mojo-residue-test.mlir`, so that the importer's
fixtures are what this compiler actually emits rather than what we think it
emits. Re-capture with:

```bash
kgen --elaborate -S -O1 -I ../hlep -mlir-print-op-generic s2residue.mojo -o -
```

and strip the module attribute dictionary, which is this machine's build
environment and nothing to do with the residue.
"""

from hlep import Bit, Lin, LinBit, U4, cx, make_qubit, measure


@export("cx_pair")
def cx_pair(var control: Lin, var target: Lin) abi("C") -> Bool:
    """A region body with a move inside an `if`, and a carry-out split."""
    cx(control, target)
    var first = measure(control^)
    var second = measure(target^)
    return first and second


@export("classify")
def classify(value: U4) abi("C") -> Bool:
    """Signedness comes off the Mojo dtype, not off the builtin type."""
    return value == 10 or value < 3


@export("widen")
def widen(bit: Bool, shift: U4) abi("C") -> U4:
    """Widening, shifting and narrowing, all by dtype."""
    var wide = SIMD[DType._uint1, 1](
        mlir_value=__mlir_op.`pop.cast_from_builtin`[
            _type = SIMD[DType._uint1, 1]._mlir_type
        ](bit.__mlir_i1__())
    ).cast[DType._uint4]()
    return (wide << shift) >> shift
