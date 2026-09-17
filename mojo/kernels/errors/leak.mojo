"""A value assigned inside a linearization body and read after it.

Results leave a body through `prelimhlep.output`, which Mojo has no way to
know, so the assignment survives as memory and qcc rejects it by name at the
Mojo line it came from.
"""

from hlep import Bit, Lin, LinBit, discard, make_qubit


@export("leak")
def leak() abi("C") -> Bool:
    var q = make_qubit()
    var leaked = False
    __mlir_region body(bit: Bit):
        leaked = Bool(bit)
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 1, 0>}`,
            _type=None,
        ](bit)

    var out = Lin(
        raw=__mlir_op.`prelimhlep.lin`[_region="body".value, _type=LinBit](
            q^._take()
        )
    )
    discard(out^)
    return leaked
