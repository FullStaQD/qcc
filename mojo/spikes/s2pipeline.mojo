"""The smallest whole kernel: allocate a qubit, flip it, measure it.

Elaborated and captured into
`mlir/test/tools/qcc-opt/mojo-residue-pipeline-test.mlir`, which runs it
through the residue translation and the existing PrelimHLEP pipeline.
"""

from hlep import make_qubit, measure, x


@export("flip")
def flip() abi("C") -> Bool:
    return measure(x(make_qubit()))
