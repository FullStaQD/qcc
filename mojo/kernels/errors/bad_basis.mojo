"""An X-basis constant that is not one.

Mojo registers the PrelimHLEP dialect but not its verifiers: quantum
semantics are qcc's, checked once, in qcc. The error still names the Mojo
line the constant was written on.
"""

from hlep import Bit, Lin, LinBit, LinXBit, make_qubit


@export("bad_basis")
def bad_basis() abi("C") -> Lin:
    var q = make_qubit()
    __mlir_region body(bit: Bit):
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 0, 1>}`,
            _type=None,
        ](
            __mlir_op.`prelimhlep.constant`[
                value = __mlir_attr.`"?"`, _type=LinXBit
            ]()
        )

    var in_x_basis = __mlir_op.`prelimhlep.lin`[
        _region="body".value, _type=LinXBit
    ](q^._take())
    return Lin(raw=__mlir_op.`prelimhlep.base_change`[_type=LinBit](in_x_basis))
