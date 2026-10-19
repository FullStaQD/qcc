from qrisp import QuantumVariable, cx, h, measure, q_cond, x

def repetition_code_bell():
    """Logical Bell pair on the 3-qubit repetition code, error corrected after every gate."""

    def flip(qubit):
        x(qubit)

    def keep(qubit):
        pass

    def encode_plus(block):
        """|000> -> (|000> + |111>) / sqrt(2), the logical |+>."""
        h(block[0])
        cx(block[0], block[1])
        cx(block[0], block[2])

    def transversal_cx(control, target):
        for i in range(3):
            cx(control[i], target[i])

    def correct(block):
        """One round: extract the syndrome into fresh ancillas, flip the data qubit it points at."""
        ancillas = QuantumVariable(2)

        cx(block[0], ancillas[0])
        cx(block[1], ancillas[0])
        cx(block[1], ancillas[1])
        cx(block[2], ancillas[1])

        syndrome = measure(ancillas)
        ancillas.delete()

        q_cond(syndrome == 1, flip, keep, block[0])
        q_cond(syndrome == 3, flip, keep, block[1])
        q_cond(syndrome == 2, flip, keep, block[2])

        return syndrome

    a = QuantumVariable(3)
    b = QuantumVariable(3)

    encode_plus(a)
    x(a[1])  # error: both ancillas of `a` see it, syndrome 0b11
    syndrome_a = correct(a)
    correct(b)

    transversal_cx(a, b)
    x(b[2])  # error: only the second ancilla of `b` sees it, syndrome 0b10
    correct(a)
    syndrome_b = correct(b)

    result_a = measure(a)
    result_b = measure(b)

    return result_a, result_a ^ result_b, syndrome_a, syndrome_b
