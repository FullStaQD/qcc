from qrisp import QuantumVariable, h, cx, measure, q_fori_loop

def prepare_bell_pairs():
    """Eight Bell pairs, written out one gate at a time."""
    n = 8
    ctrls = QuantumVariable(n)
    tgts = QuantumVariable(n)

    def entangle(i, qvs):
        ctrls, tgts = qvs
        cx(ctrls[i], tgts[i])
        return qvs

    # For now OK to just unroll these loops:
    q_fori_loop(0, n, lambda i, qv: (h(qv[i]), qv)[1], ctrls)
    q_fori_loop(0, n, entangle, (ctrls, tgts))

    # Both halves of a Bell pair collapse to the same value, so -- errors
    # aside -- the two registers have to agree.
    return measure(ctrls) == measure(tgts)
