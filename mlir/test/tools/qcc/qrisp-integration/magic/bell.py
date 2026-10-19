from qrisp import QuantumVariable, h, cx, measure

def bell():
    """A Bell pair: both ions fit into one trap, no shuttling."""
    qv = QuantumVariable(2)

    h(qv[0])
    cx(qv[0], qv[1])

    return measure(qv)
