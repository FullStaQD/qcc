# Spike: does `Lin[E]` elaborate to a concrete `!prelimhlep.lin<...>` at a
# concrete call site now that the dialect is registered?
#
# While `prelimhlep` was unregistered, `!prelimhlep.lin<!kgen.param<n>>` was an
# `OpaqueType` with an uninterpreted string payload, so the elaborator's
# sub-element walk could not reach the parameter and `EnsureNoParameters` could
# not see the leak. Registered, `LinType` has a real `Type` parameter, so the
# `AttrTypeReplacer` substitutes it like any other.


struct Lin[E: __mlir_type.`!kgen.type`](
    RegisterPassable, Movable, Deinitable where False
):
    comptime _mlir_type = __mlir_type[`!prelimhlep.lin<`, Self.E, `>`]

    var _v: Self._mlir_type

    @always_inline
    def __init__(out self, *, raw: Self._mlir_type):
        self._v = raw

    @always_inline
    def _take(deinit self) -> Self._mlir_type:
        return self._v


# Generic over the basis element type: one body, instantiated per width. No
# `__mlir_region` here -- see `identity` below for the gap that blocks that.
def relabel[E: __mlir_type.`!kgen.type`](var q: Lin[E]) -> Lin[E]:
    return Lin[E](raw=q^._take())


@export("use_i1")
def use_i1(var q: Lin[__mlir_type.i1]) -> Lin[__mlir_type.i1]:
    return relabel[__mlir_type.i1](q^)


@export("use_i8")
def use_i8(var q: Lin[__mlir_type.i8]) -> Lin[__mlir_type.i8]:
    return relabel[__mlir_type.i8](q^)


# KNOWN GAP (phase 2): a `__mlir_region` whose block argument is typed by a
# parameter is rejected before elaboration ever runs --
#
#     __mlir_region body(bits: E):
#         ...
#     s1generic.mojo:NN: error: cannot load non-register passable type into
#     SSA register (compiler bug, please report!)
#
# The parser decides register-passability of a `__mlir_region` argument at
# parse time, where `E` is still `!kgen.param<...>`. That is a parser question,
# not a substitution one: the struct above shows substitution works. Until it
# is fixed, a generic primitive must take its body's basis type concretely.
