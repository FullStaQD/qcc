from qrisp import QuantumVariable, h, cx, measure, q_fori_loop

def prepare_ghz():
    n = 3
    qv = QuantumVariable(n)

    h(qv[0])

    # For now OK to just unroll this loop:
    q_fori_loop(1, n, lambda i, qv: (cx(qv[i-1], qv[i]), qv)[1], qv)

    m = measure(qv)

    return m
