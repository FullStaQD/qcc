// REQUIRES: hisepq-sim

// Runs `qrisp-integration/hisepq/repetition_code.mlir` on the simulator, with the outcomes of an ideal device:
// syndrome 11 in round 1, both ancillas still 1 when reset, syndrome 00 in round 2 and 000 for the data qubits. The
// testbench fails unless the pulses are those listed: the error, two rounds of four CX, the correction of qubit 1, the
// ancilla resets and the measurements. For the plusargs and the file formats see `mlir/lib/Target/HiSEPQ/README.md`.

// RUN: qcc --target=hisepq --compile-to=native --binary %S/../qrisp-integration/hisepq/repetition_code.mlir -o %t.o
// RUN: ld.lld -T %project_source_dir/mlir/lib/Target/HiSEPQ/Scripts/hisepq.ld %t.o -o %t.elf
// RUN: hisepq-elf2mem %t.elf -o %t.mem
// RUN: sed 's/#.*//' %S/Inputs/repetition_code.outcomes > %t.outcomes
// RUN: sed 's/#.*//' %S/Inputs/repetition_code.expect > %t.expect
// RUN: sim_hisepq +MEM_FILE=%t.mem +MEASURE_FILE=%t.outcomes +AWG_EXPECT=%t.expect | FileCheck %s

// CHECK: [PASS][AWG_EXPECT] all 29 expected fires matched exactly
// CHECK: measurements   : 7
// CHECK: RESULT : PASS
