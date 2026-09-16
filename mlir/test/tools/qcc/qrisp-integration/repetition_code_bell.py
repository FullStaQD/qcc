from qrisp import QuantumVariable, cx, h, measure, q_cond, x

def repetition_code_bell():
    """A Bell state of two logical qubits of the 3-qubit repetition code, error corrected between the gates.

    The first block is encoded into logical |+>, then a transversal CNOT entangles it with the second
    block, still in logical |0>. Each block goes through a correction round after every gate. A bit
    flip is injected before each round, so the rounds have something to correct.
    """

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

    # `result_a` is 0 or 7 at random; being a Bell pair, `result_b` is the same.
    return result_a, result_a ^ result_b, syndrome_a, syndrome_b
