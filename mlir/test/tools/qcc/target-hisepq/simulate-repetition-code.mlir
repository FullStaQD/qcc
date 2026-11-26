// REQUIRES: hisepq-sim

// Runs `qrisp-integration/hisepq/repetition_code.mlir` with the outcomes of an ideal device and checks the pulses.
// The file formats are described in `mlir/lib/Target/HiSEPQ/README.md`.

// RUN: qcc --target=hisepq --compile-to=native --binary %S/../qrisp-integration/hisepq/repetition_code.mlir -o %t.o
// RUN: ld.lld -T %project_source_dir/mlir/lib/Target/HiSEPQ/Scripts/hisepq.ld %t.o -o %t.elf
// RUN: hisepq-elf2mem %t.elf -o %t.mem
// RUN: sed 's/#.*//' %S/Inputs/repetition_code.outcomes > %t.outcomes
// RUN: sed 's/#.*//' %S/Inputs/repetition_code.expect > %t.expect
// RUN: sim_hisepq +MEM_FILE=%t.mem +MEASURE_FILE=%t.outcomes +AWG_EXPECT=%t.expect | FileCheck %s

// CHECK: [PASS][AWG_EXPECT] all 29 expected fires matched exactly
// CHECK: measurements   : 7
// CHECK: RESULT : PASS
