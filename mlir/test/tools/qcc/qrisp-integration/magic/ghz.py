from qrisp import QuantumVariable, h, cx, measure

def ghz():
    """A GHZ state on 3 qubits: on a device whose first trap is too small the ions spread over two traps."""
    n = 3
    qv = QuantumVariable(n)

    h(qv[0])
    for i in range(1, n):
        cx(qv[i - 1], qv[i])

    return measure(qv)
