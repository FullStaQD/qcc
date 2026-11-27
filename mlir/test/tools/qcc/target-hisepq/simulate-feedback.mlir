// REQUIRES: hisepq-sim

// The program branches on a measurement outcome, which the testbench injects via `+MEASURE_RESULT=0|1`. Only outcome
// 1 fires the X. The testbench fails on missing or extra pulses, but doesn't check their order. The file format is
// described in `mlir/lib/Target/HiSEPQ/README.md`.

// RUN: qcc --target=hisepq --compile-to=native --binary %s -o %t.o
// RUN: ld.lld -T %project_source_dir/mlir/lib/Target/HiSEPQ/Scripts/hisepq.ld %t.o -o %t.elf
// RUN: hisepq-elf2mem %t.elf -o %t.mem
// RUN: sed 's/#.*//' %S/Inputs/feedback-outcome-0.expect > %t.outcome-0.expect
// RUN: sed 's/#.*//' %S/Inputs/feedback-outcome-1.expect > %t.outcome-1.expect
// RUN: sim_hisepq +MEM_FILE=%t.mem +MEASURE_RESULT=0 +AWG_EXPECT=%t.outcome-0.expect | FileCheck %s
// RUN: sim_hisepq +MEM_FILE=%t.mem +MEASURE_RESULT=1 +AWG_EXPECT=%t.outcome-1.expect | FileCheck %s

func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    qc.h %0 : !qc.qubit
    %m = qc.measure %0 : !qc.qubit -> i1
    scf.if %m {
        qc.x %0 : !qc.qubit
    }
    // Without a record, the whole program would be erased as dead code.
    %r = qc.measure %0 : !qc.qubit -> i1
    aux.record_int %r : i1
    return
}

// CHECK: [PASS][AWG_EXPECT] all {{[0-9]+}} expected fires matched exactly
// CHECK: RESULT : PASS
