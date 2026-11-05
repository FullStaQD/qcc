// REQUIRES: lld, sim-hisepq

// The program branches on a measurement outcome, which the testbench supplies (`+MEASURE_RESULT`). The testbench also
// compares the pulses with the exact list in `+AWG_EXPECT` (one line per pulse: qubit, gate id, role, whether a
// payload is checked, payload) and fails on any missing or unexpected one. Only outcome 1 adds the X (gate id 0x02).

// RUN: qcc --target=hisepq --compile-to=native --binary %s -o %t.o
// RUN: ld.lld -T %project_source_dir/mlir/lib/Target/HiSEPQ/Scripts/hisepq.ld %t.o -o %t.elf
// RUN: hisepq-elf2mem %t.elf -o %t.mem
// RUN: sim_hisepq +MEM_FILE=%t.mem +MEASURE_RESULT=0 +AWG_EXPECT=%S/Inputs/feedback-outcome-0.expect | FileCheck %s
// RUN: sim_hisepq +MEM_FILE=%t.mem +MEASURE_RESULT=1 +AWG_EXPECT=%S/Inputs/feedback-outcome-1.expect | FileCheck %s

func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    qc.h %0 : !qc.qubit
    %m = qc.measure %0 : !qc.qubit -> i1
    scf.if %m {
        qc.x %0 : !qc.qubit
    }
    return
}

// CHECK: [PASS][AWG_EXPECT] all {{[0-9]+}} expected fires matched exactly
// CHECK: RESULT : PASS
