from qrisp import QuantumVariable, cx, measure, q_cond, q_fori_loop, x

def repetition_code():
    """Multi-round error correction on the 3-qubit bit-flip repetition code."""
    rounds = 3
    data = QuantumVariable(3)

    x(data[1])  # error: both ancillas see it, syndrome 0b11

    def flip(qubit):
        x(qubit)

    def keep(qubit):
        pass

    def correct(round, syndrome_history):
        ancillas = QuantumVariable(2)

        cx(data[0], ancillas[0])
        cx(data[1], ancillas[0])
        cx(data[1], ancillas[1])
        cx(data[2], ancillas[1])

        syndrome = measure(ancillas)
        ancillas.delete()

        q_cond(syndrome == 1, flip, keep, data[0])
        q_cond(syndrome == 3, flip, keep, data[1])
        q_cond(syndrome == 2, flip, keep, data[2])

        return syndrome_history | (syndrome << (2 * round))

    syndrome_history = q_fori_loop(0, rounds, correct, 0)

    return syndrome_history, measure(data)
