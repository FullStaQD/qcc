# ===----------------------------------------------------------------------=== #
#
# Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
# Exceptions.
# See <repo-root>/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# ===----------------------------------------------------------------------=== #
"""Grover search over four qubits, written in Mojo.

The same program as `mlir/test/tools/qcc-opt/prelim-hlep-to-qco-grover-test.mlir`,
and it lowers to the same QCO circuit. That is the point of the file: the
Mojo frontend is a way of writing PrelimHLEP, not a second language with its
own semantics.
"""

from hlep import U4, diffusion4, measure4, phase_tag4, uniform4


@always_inline
def is_ten(value: U4) -> Bool:
    """The oracle: marks the single element 10 = 0b1010."""
    return value == 10


@export("grover")
def grover() abi("C") -> U4:
    """Prepare the uniform superposition, then alternate oracle phase tags
    with inversions about the mean for the optimal round(pi/4 * sqrt(16)) = 3
    iterations, and measure. The result is 10 with probability ~0.958."""
    # TODO: use a loop for the iterations once `hlcf.loop` is in the table.
    var state = uniform4()
    state = diffusion4(phase_tag4[is_ten](state^))
    state = diffusion4(phase_tag4[is_ten](state^))
    state = diffusion4(phase_tag4[is_ten](state^))
    return measure4(state^)
