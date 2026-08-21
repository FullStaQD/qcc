// REQUIRES: lld, sim-hisepq

// Full HiSEP-Q integration test: compile, link, convert to memory image, then
// actually execute that image on the prebuilt RTL testbench.

// RUN: qcc --target=hisepq --compile-to=native --binary %s -o %t.o
// RUN: ld.lld -T %project_source_dir/mlir/lib/Target/HiSEPQ/Scripts/hisepq.ld %t.o -o %t.elf
// RUN: hisepq-elf2mem %t.elf -o %t.mem
// RUN: sim_hisepq +MEM_FILE=%t.mem | FileCheck %s

func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    qc.h %0 : !qc.qubit
    %m = qc.measure %0 : !qc.qubit -> i1
    aux.record_int %m : i1
    return
}

// `sim_hisepq` exits 0 unconditionally -- with no memory image at all it still
// reports `RESULT: PASS`, having executed nothing. So we have to assert on the
// trace and on the event counters.

// FIXME: watch out for things to also check

// CHECK:      [INIT] mem file:
// CHECK:      [INSTR] 00001537  lui a0, 0x1
// CHECK:      [MEASURE] qvsg_meas=1 start
// CHECK:      quantum events : 2
// CHECK-NEXT: qubit fires    : 2
// CHECK-NEXT: FIFO errors    : 0
