# ===----------------------------------------------------------------------=== #
#
# Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
# Exceptions.
# See <repo-root>/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# ===----------------------------------------------------------------------=== #
"""The PrelimHLEP eDSL: quantum kernels written in Mojo, compiled by qcc.

A kernel is ordinary Mojo. Linearity is Mojo's job: `Lin` is neither
`Copyable` (so using a qubit twice is "use of uninitialized value") nor
`Deinitable` (so dropping one is an error naming what to do instead).
Quantum semantics are qcc's job: the IR this library emits goes through
`qcc-opt --mojo-residue-to-std` into the PrelimHLEP pipeline, and every
diagnostic from there points back at the Mojo line it came from.

Nothing here executes at runtime to build a circuit. A `__mlir_region` body
is compiled once into the region of a `prelimhlep.lin` op; a Mojo `if` inside
one is an `scf.if` in the IR. This is not tracing.

A body may not contain an early `return` (it ends in `prelimhlep.output`),
and may not assign an outer variable that is read after the body (results
leave a body through `prelimhlep.output`). Both are reported by qcc's
`--mojo-residue-to-std` at the Mojo line they came from.

`Lin` is monomorphic over `i1` and `Reg4` over `i4` rather than one `Lin[E]`:
the elaborator substitutes into `!prelimhlep.lin<E>` correctly now that the
dialect is registered, but a `__mlir_region` block argument cannot yet be
typed by a parameter, and every gate here binds one. See
`../spikes/s1generic.mojo`.
"""


# ===----------------------------------------------------------------------=== #
# The MLIR types this library is written over
# ===----------------------------------------------------------------------=== #

comptime Bit = __mlir_type.i1
"""One qubit's classical fibre: the computational basis of a single qubit."""

comptime Bits4 = __mlir_type.i4
"""A four-qubit register's classical fibre."""

comptime LinBit = __mlir_type.`!prelimhlep.lin<i1>`
comptime LinBits4 = __mlir_type.`!prelimhlep.lin<i4>`
comptime LinXBit = __mlir_type.`!prelimhlep.lin<!prelimhlep.x<1>>`
comptime LinBitQuad = __mlir_type.`!kgen.struct<(!prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>)>`
"""Four qubits as one MLIR value. Written as a `kgen.struct` rather than
a Mojo `Tuple` because Mojo builds a four-element tuple through a pointer,
which would leave a `pop.store` of a linear value in the IR."""
comptime Unit = __mlir_type.`!prelimhlep.unit`
comptime Complex64 = __mlir_type.`complex<f64>`

comptime U1 = SIMD[DType._uint1, 1]
"""One classical bit, as Mojo arithmetic."""

comptime U4 = SIMD[DType._uint4, 1]
"""The Mojo view of `Bits4`, so that a four-qubit register's classical
residue is ordinary Mojo arithmetic rather than raw inline MLIR."""


# ===----------------------------------------------------------------------=== #
# Linear values
# ===----------------------------------------------------------------------=== #


@explicit_destroy(
    "quantum values must be consumed: 'measure()', 'discard()', or pass it on"
)
struct Lin(RegisterPassable, Movable, Deinitable where False):
    """A single qubit.

    Not `Copyable`, so a second use of one is a Mojo "use of uninitialized
    value"; not `Deinitable`, so dropping one is the message above. qcc's
    single-use verifier stays as the second line of defence, and its errors
    still point at the Mojo line.
    """

    var _v: LinBit

    @always_inline
    def __init__(out self, *, raw: LinBit):
        self._v = raw

    @always_inline
    def _take(deinit self) -> LinBit:
        """The only consumer: takes the value and ends this binding's life."""
        return self._v


@explicit_destroy("quantum registers must be consumed: 'measure4()' or split it")
struct Reg4(RegisterPassable, Movable, Deinitable where False):
    """Four qubits held as one linear value over `i4`."""

    var _v: LinBits4

    @always_inline
    def __init__(out self, *, raw: LinBits4):
        self._v = raw

    @always_inline
    def _take(deinit self) -> LinBits4:
        return self._v


@explicit_destroy("the halo must be returned")
struct Halo(RegisterPassable, Movable, Deinitable where False):
    """The tensor unit. A haloed function with nothing else to take or give
    takes and gives this, because the halo rule forbids a nullary one."""

    var _v: Unit


# ===----------------------------------------------------------------------=== #
# Primitive gates
# ===----------------------------------------------------------------------=== #


def make_qubit() -> Lin:
    """A fresh qubit in the |0> state."""
    __mlir_region body():
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 1, 0>}`,
            _type=None,
        ](False.__mlir_i1__())

    return Lin(
        raw=__mlir_op.`prelimhlep.lin`[_region="body".value, _type=LinBit]()
    )


def x(var q: Lin) -> Lin:
    """The Pauli X gate: flips the computational basis."""
    __mlir_region body(bit: Bit):
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 1, 0>}`,
            _type=None,
        ]((not Bool(bit)).__mlir_i1__())

    return Lin(
        raw=__mlir_op.`prelimhlep.lin`[_region="body".value, _type=LinBit](
            q^._take()
        )
    )


def h(var q: Lin) -> Lin:
    """The Hadamard gate: the change of basis between Z and X.

    The body maps each computational basis state to an X-basis constant, so
    the linearization lands in the X basis; `base_change` names the two
    linearizations as the same space.
    """
    __mlir_region body(bit: Bit):
        var out_x: LinXBit
        if Bool(bit):
            out_x = __mlir_op.`prelimhlep.constant`[
                value = __mlir_attr.`"+"`, _type=LinXBit
            ]()
        else:
            out_x = __mlir_op.`prelimhlep.constant`[
                value = __mlir_attr.`"-"`, _type=LinXBit
            ]()
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 0, 1>}`,
            _type=None,
        ](out_x)

    var in_x_basis = __mlir_op.`prelimhlep.lin`[
        _region="body".value, _type=LinXBit
    ](q^._take())
    return Lin(
        raw=__mlir_op.`prelimhlep.base_change`[_type=LinBit](in_x_basis)
    )


@always_inline
def cx(mut control: Lin, mut target: Lin):
    """Controlled X: the target is moved into the body and flipped there.

    A gate with several qubits both in and out takes them `mut` and writes
    them back, because a linear value cannot be moved out of a Mojo tuple or
    out of the middle of a struct. Single-qubit gates keep the `var q` ->
    `Lin` shape, which reads better where it works.

    `@always_inline` is not an optimization here: a `mut` parameter is a
    pointer, and Mem2Reg cannot promote a qubit that is passed through one,
    so an out-of-line call would hand qcc `pop.load` of a linear value.
    """
    # Moved out of the `mut` binding before the region: what a body writes
    # does not leave it, so a slot written inside and read outside stays in
    # memory. `inner` is written and read only inside.
    var inner = target^
    __mlir_region body(control_bit: Bit):
        if Bool(control_bit):
            inner = x(inner^)
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 1, 1>}`,
            _type=None,
        ](control_bit, inner^._take())

    var out = __mlir_op.`prelimhlep.lin`[
        _region="body".value, _type=Tuple[LinBit, LinBit]
    ](control^._take())
    control = Lin(raw=out[0])
    target = Lin(raw=out[1])


def measure(var q: Lin) -> Bool:
    """Measure one qubit in the computational basis and consume it."""
    __mlir_region body(bit: Bit):
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 0, 1>}`,
            _type=None,
        ](bit)

    return Bool(
        __mlir_op.`prelimhlep.lin`[_region="body".value, _type=Bit](
            q^._take()
        )
    )


def discard(var q: Lin):
    """Forget a qubit. The forget map is a call, so it is always in the IR."""
    __mlir_region body(bit: Bit):
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 0, 0>}`,
            _type=None,
        ]()

    __mlir_op.`prelimhlep.lin`[_region="body".value, _type=None](q^._take())


# ===----------------------------------------------------------------------=== #
# Four-qubit registers
#
# `Reg4` is the same four qubits as four `Lin`s, held over `i4` instead: the
# classical residue inside a body is then ordinary `U4` arithmetic, and
# `split4`/`combine4` are the two halves of the isomorphism.
# ===----------------------------------------------------------------------=== #


@always_inline
def _u4(raw: Bits4) -> U4:
    """`Bits4` seen as Mojo arithmetic."""
    return U4(
        mlir_value=__mlir_op.`pop.cast_from_builtin`[_type = U4._mlir_type](raw)
    )


@always_inline
def _raw4(value: U4) -> Bits4:
    """The inverse of `_u4`."""
    return __mlir_op.`pop.cast_to_builtin`[_type=Bits4](value._mlir_value)


@always_inline
def _widen(bit: Bit) -> U4:
    """One classical bit as the low bit of a four-bit word, by zero extension."""
    return U1(
        mlir_value=__mlir_op.`pop.cast_from_builtin`[_type = U1._mlir_type](bit)
    ).cast[DType._uint4]()


@always_inline
def _narrow(value: U4) -> Bit:
    """The low bit of a four-bit word, by truncation.

    Not `value & 1 != 0`: a comparison inside a linearization body is not one
    of the normal-form shapes `prelim-hlep-normalize-lin` decomposes, and the
    truncation says the same thing in the vocabulary the pipeline has.
    """
    return __mlir_op.`pop.cast_to_builtin`[_type=Bit](
        value.cast[DType._uint1]()._mlir_value
    )


struct Quad(RegisterPassable, Movable, Deinitable where False):
    """Four qubits, held one by one.

    The register a `Reg4` holds, taken apart. Its fields are ordinary `Lin`
    bindings, so a gate can take one `mut`; the whole `Quad` goes back into a
    `Reg4` with `combine4`.
    """

    var q0: Lin
    var q1: Lin
    var q2: Lin
    var q3: Lin

    @always_inline
    def __init__(out self, var q0: Lin, var q1: Lin, var q2: Lin, var q3: Lin):
        self.q0 = q0^
        self.q1 = q1^
        self.q2 = q2^
        self.q3 = q3^

    @always_inline
    def _combine(deinit self) -> Reg4:
        """The only consumer; `combine4` is its public name.

        The four qubits are taken here rather than by the caller for two
        reasons: taking them one by one from outside is "destroyed out of the
        middle of a value", and handing them back as a Mojo `Tuple` builds
        the tuple through a pointer, which leaves `pop.store` of a
        `!prelimhlep.lin<i1>` in the IR for qcc to reject.
        """
        __mlir_region body(b0: Bit, b1: Bit, b2: Bit, b3: Bit):
            var bits = (
                _widen(b0)
                | (_widen(b1) << 1)
                | (_widen(b2) << 2)
                | (_widen(b3) << 3)
            )
            __mlir_op.`prelimhlep.output`[
                _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 1, 0>}`,
                _type=None,
            ](_raw4(bits))

        return Reg4(
            raw=__mlir_op.`prelimhlep.lin`[
                _region="body".value, _type=LinBits4
            ](
                self.q0^._take(),
                self.q1^._take(),
                self.q2^._take(),
                self.q3^._take(),
            )
        )


def combine4(var q: Quad) -> Reg4:
    """Four qubits as one register, `q0` least significant."""
    return q^._combine()


def split4(var reg: Reg4) -> Quad:
    """The inverse of `combine4`."""
    __mlir_region body(bits: Bits4):
        var value = _u4(bits)
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 4, 0>}`,
            _type=None,
        ](
            _narrow(value),
            _narrow(value >> 1),
            _narrow(value >> 2),
            _narrow(value >> 3),
        )

    var out = __mlir_op.`prelimhlep.lin`[
        _region="body".value, _type=LinBitQuad
    ](reg^._take())
    return Quad(
        Lin(raw=__mlir_op.`kgen.struct.extract`[
            index = __mlir_attr.`0 : index`, _type=LinBit
        ](out)),
        Lin(raw=__mlir_op.`kgen.struct.extract`[
            index = __mlir_attr.`1 : index`, _type=LinBit
        ](out)),
        Lin(raw=__mlir_op.`kgen.struct.extract`[
            index = __mlir_attr.`2 : index`, _type=LinBit
        ](out)),
        Lin(raw=__mlir_op.`kgen.struct.extract`[
            index = __mlir_attr.`3 : index`, _type=LinBit
        ](out)),
    )


def h4(var reg: Reg4) -> Reg4:
    """Hadamard on each of the four qubits."""
    var q = split4(reg^)
    q.q0 = h(q.q0^)
    q.q1 = h(q.q1^)
    q.q2 = h(q.q2^)
    q.q3 = h(q.q3^)
    return combine4(q^)


def uniform4() -> Reg4:
    """The uniform superposition over all sixteen basis states."""
    return h4(
        combine4(
            Quad(make_qubit(), make_qubit(), make_qubit(), make_qubit())
        )
    )


@always_inline
def _minus_one() -> Complex64:
    """The scalar -1, as `prelimhlep.scale` takes it."""
    return __mlir_op.`complex.constant`[
        value = __mlir_attr.`[-1.000000e+00 : f64, 0.000000e+00 : f64]`,
        _type=Complex64,
    ]()


def phase_tag4[oracle: def (U4) thin -> Bool](var reg: Reg4) -> Reg4:
    """Flip the phase of exactly the basis states `oracle` marks.

    The oracle is an ordinary Mojo function, called inside the body; the
    call imports as a `func.call` and qcc's inliner flattens it.
    """
    __mlir_region body(bits: Bits4):
        var tagged = bits
        if oracle(_u4(bits)):
            tagged = __mlir_op.`prelimhlep.scale`[_type=Bits4](
                _minus_one(), bits
            )
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 1, 0>}`,
            _type=None,
        ](tagged)

    return Reg4(
        raw=__mlir_op.`prelimhlep.lin`[_region="body".value, _type=LinBits4](
            reg^._take()
        )
    )


@always_inline
def _is_zero(value: U4) -> Bool:
    return value == 0


def diffusion4(var reg: Reg4) -> Reg4:
    """Inversion about the mean: H^4 (2|0><0| - 1) H^4, up to global phase."""
    return h4(phase_tag4[_is_zero](h4(reg^)))


def measure4(var reg: Reg4) -> U4:
    """Measure all four qubits at once and consume the register."""
    __mlir_region body(bits: Bits4):
        __mlir_op.`prelimhlep.output`[
            _properties=__mlir_attr.`{operandSegmentSizes = array<i32: 0, 1>}`,
            _type=None,
        ](bits)

    return _u4(
        __mlir_op.`prelimhlep.lin`[_region="body".value, _type=Bits4](
            reg^._take()
        )
    )
