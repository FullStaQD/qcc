# ===----------------------------------------------------------------------=== #
#
# Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
# Exceptions.
# See <repo-root>/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# ===----------------------------------------------------------------------=== #
"""The host half of a quantum program.

`hlep` is what a kernel is written in; `qpu.host` is what the host code around
it uses to run one. The two never meet in the same function: a kernel is
compiled by qcc and reaches the host program as an artifact, and `qpu.host`
picks a device and submits it.
"""

from .host import Device, Histogram, Job, QPUContext, artifact_of
