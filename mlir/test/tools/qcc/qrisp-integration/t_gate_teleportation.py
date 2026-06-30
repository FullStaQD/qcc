from qrisp import QuantumVariable, h, s, t, t_dg, cx, measure, q_cond

def t_gate_teleportation():
    """Exercises forward branching based on measurement (if-else)."""
    qv = QuantumVariable(2)
    ancilla, data = qv[0], qv[1]

    h(data)  # initialize data into |0> + |1> state.

    h(ancilla)
    t(ancilla)  # cheating: prepare magic state

    cx(data, ancilla)

    m0 = measure(ancilla)
    q_cond(m0 == 1, lambda q: (s(q), None)[1], lambda q: None, data)  # if statement

    # Just to check for correctness:
    t_dg(data)
    h(data)  # data should now be in |0> state
    m1 = measure(data)

    return m1  # should return 0
