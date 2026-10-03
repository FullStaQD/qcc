import numpy as np
from qrisp import QuantumVariable, h, p, cp, measure

def qft():
    """A QFT on 4 qubits (no final swaps) with a deterministic outcome.

    The input is the inverse Fourier transform of the basis state |k>, a
    product state, so the QFT yields |k> again. The first qubit is the most
    significant one for the QFT. Without the final swaps the result comes out
    bit-reversed, which is the order `measure` reads it in: the output is k.
    """
    n = 4
    k = 5
    qv = QuantumVariable(n)

    # The inverse Fourier transform of |k>: sum_y exp(-2 pi i k y / 2^n) |y>.
    for j in range(n):
        h(qv[j])
        p(-2 * np.pi * k * 2 ** (n - 1 - j) / 2**n, qv[j])

    # The QFT itself.
    for i in range(n):
        h(qv[i])
        for j in range(i + 1, n):
            cp(np.pi / 2 ** (j - i), qv[j], qv[i])

    return measure(qv)
