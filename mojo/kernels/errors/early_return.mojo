"""An early `return` inside a linearization body.

A body ends in `prelimhlep.output`; there is no partial exit from one. The
construct is a Mojo `return` in an `scf.if`, which `scf.if` cannot express,
so qcc rejects it by name at the Mojo line.
"""

from hlep import Bit, Lin, LinBit, make_qubit


@export("early_return")
def early_return() abi("C") -> Bool:
    var q = make_qubit()
    __mlir_region body(bit: Bit):
        if Bool(bit):
            return False
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 0, 1>}`,
            _type=None,
        ](bit)

    return Bool(
        __mlir_op.`prelimhlep.lin`[_region="body".value, _type=Bit](q^._take())
    )
