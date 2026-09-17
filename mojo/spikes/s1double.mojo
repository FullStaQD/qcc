comptime LinBool = __mlir_type.`!prelimhlep.lin<i1>`


@explicit_destroy("quantum values must be consumed: 'measure()', 'discard()', or pass it on")
struct Lin(RegisterPassable, Movable, Deinitable where False):
    var _v: LinBool

    @always_inline
    def __init__(out self, *, raw: LinBool):
        self._v = raw

    @always_inline
    def _take(deinit self) -> LinBool:
        return self._v


def x(var q: Lin) -> Lin:
    __mlir_region body(bit: __mlir_type.i1):
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 1, 0>}`,
            _type=None,
        ](
            (not Bool(bit)).__mlir_i1__()
        )

    return Lin(
        raw=__mlir_op.`prelimhlep.lin`[_region="body".value, _type=LinBool](
            q^._take()
        )
    )


@export("cx")
def cx(var control: Lin, var target: Lin) -> Tuple[Lin, Lin]:
    __mlir_region body(control_bit: __mlir_type.i1):
        if Bool(control_bit):
            target = x(target^)
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 1, 2>}`,
            _type=None,
        ](
            control_bit, target^._take(), target^._take()
        )

    var out = __mlir_op.`prelimhlep.lin`[
        _region="body".value, _type=Tuple[LinBool, LinBool]
    ](control^._take())
    return Lin(raw=out[0]), Lin(raw=out[1])
