from math import pi
from qrisp import QuantumVariable, control, cp, h, q_fori_loop, reset, rz, x, measure, jrange

def iqpe():
    target_phase = 0.3125 # 0.0101
    precision = 4

    eigenstate = QuantumVariable(1)
    x(eigenstate[0])  # Use |1> as eigenstate for phase unitary

    phase_digit = QuantumVariable(1)
    measured_digits = 0

    def get_digit(i, iter_args):
        measured_digits, phase_digit, target_phase, eigenstate, precision = iter_args

        reset(phase_digit[0])
        h(phase_digit[0])
        cp(pi * target_phase * 2.0**(precision - i), phase_digit[0], eigenstate[0])

        for j in jrange(i):
            with control(((measured_digits >> j) & 1) == 1):
                rz(-pi * 2.0**(j - i), phase_digit[0])
                # Beware that the base for exponentiation must be float:
                # 2**(...) in the jasp tracer interprets the exponent as
                # unsigned i64. Hence e.g. 2**(-2) evaluates to 2**(62) (this is
                # what happened when we tested it).

        h(phase_digit[0])
        measured_digits = measured_digits | (measure(phase_digit) << i)
        return measured_digits, phase_digit, target_phase, eigenstate, precision

    measured_digits, *_ = q_fori_loop(
        lower=0,
        upper=precision,
        body_fun=get_digit,
        init_val=(measured_digits, phase_digit, target_phase, eigenstate, precision)
    )

    return measured_digits
