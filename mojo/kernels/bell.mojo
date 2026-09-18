# ===----------------------------------------------------------------------=== #
#
# Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
# Exceptions.
# See <repo-root>/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# ===----------------------------------------------------------------------=== #
"""A Bell pair, written in Mojo, launched from the host in the same file.

The smallest program that exercises the whole chain end to end: `kgen`
elaborates this file, hands the kernel to `qcc`, embeds the QIR it gets back,
and compiles `main` for the CPU. At run time `qpu.host` reads the embedded
artifact through the accessors `kgen` synthesized and submits it to a device.

One kernel invocation is one shot, so the correlation that makes a Bell pair
a Bell pair is a property of the histogram, not of any single result.
"""

from hlep import Lin, cx, h, make_qubit, measure
from qpu.host import QPUContext


@export("bell")
def bell() abi("C") -> Tuple[Bool, Bool]:
    """|00> + |11>, measured. Both bits always agree."""
    var a = h(make_qubit())
    var b = make_qubit()
    cx(a, b)  # in place: see "Two shapes Mojo forces" in mojo/README.md
    return measure(a^), measure(b^)


def main() raises:
    var qpu = QPUContext(device_id=0)
    print("device:", qpu.device)

    var histogram = qpu.enqueue[bell](shots=1000).result()
    print("outcomes:", histogram)

    # The two qubits are entangled, so the only outcomes are the two the
    # kernel can produce together. A shot that disagreed with itself would
    # mean the pair was never entangled.
    var agreed = histogram.count("true, true") + histogram.count("false, false")
    print("agreed:", agreed, "of", histogram.shots, "shots")
