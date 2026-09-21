from qrisp import QuantumVariable, cx, measure, q_cond, q_fori_loop, x

def repetition_code():
    """Error correction on the 3-qubit bit-flip repetition code over several rounds.

    Every round allocates two ancillas, extracts the syndrome into them, gives them back and
    flips whichever data qubit the syndrome points at. The syndromes of all rounds are collected
    into one integer, two bits per round.
    """
    rounds = 3
    data = QuantumVariable(3)

    # A bit flip on the middle qubit, which both ancillas detect: syndrome 0b11.
    x(data[1])

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

        # Decode: each non-zero syndrome identifies one data qubit.
        q_cond(syndrome == 1, flip, keep, data[0])
        q_cond(syndrome == 3, flip, keep, data[1])
        q_cond(syndrome == 2, flip, keep, data[2])

        return syndrome_history | (syndrome << (2 * round))

    syndrome_history = q_fori_loop(0, rounds, correct, 0)

    return syndrome_history, measure(data)
