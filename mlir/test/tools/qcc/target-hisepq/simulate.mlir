// REQUIRES: lld, sim-hisepq

// Full HiSEP-Q integration test: compile, link, convert to a memory image, then actually execute that image on the
// prebuilt RTL testbench.

// RUN: qcc --target=hisepq --compile-to=native --binary %s -o %t.o
// RUN: ld.lld -T %project_source_dir/mlir/lib/Target/HiSEPQ/Scripts/hisepq.ld %t.o -o %t.elf
// RUN: hisepq-elf2mem %t.elf -o %t.mem
// RUN: sim_hisepq +MEM_FILE=%t.mem > %t.log

// Split checks into three stages for readability.
// RUN: FileCheck --check-prefix=CHECK-ISSUE --input-file=%t.log %s
// RUN: FileCheck --check-prefix=CHECK-STREAM --input-file=%t.log %s
// RUN: FileCheck --check-prefix=CHECK-AWG --input-file=%t.log %s

// ISSUE Stage: Ibex decodes classical and quantum instructions and hands over the vector and quantum ones to the
// vector coprocessor (vproc).

// STREAM Stage: vproc serializes a quantum instruction into quantum *events*, one per vector element. Hence one
// instruction on N qubits becomes N events in the stream. Each event carries op type (e.g. SINGLE, PAIR),
// instruction id, elem1/2/3 (qubit indices, gate ids, timing info).

// AWG Stage: The quantum_dispatcher consumes the event stream and drops each event into a per-qubit timed FIFO, and
// fires it when the global counter t_cnt reaches its scheduled slot. The "qubit fires" counter counts the pulses.

func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    qc.h %0 : !qc.qubit
    %m = qc.measure %0 : !qc.qubit -> i1
    aux.record_int %m : i1
    return
}

// CHECK-ISSUE: [MEASURE] qvsg_meas=1 start
// TODO(HiSEP-Q): In addition, there should be two [INSTR] lines here for the two gates (H and MZ). Unfortunately, the
// simulator only matches the *full* 32-bit instruction words (containing specific operands) as in their own Bell demo.

// TODO(HiSEP-Q): qvsg_meas=1 start actually freezes the core until measure_done arrives, and it never does. The
// testbench sends it only once the measure stream reaches qsg_measure_elem_budget(lmul), which is 8 events even at the
// smallest LMUL, whereas a single-qubit measure emits one. So the run ends on "200 idle cycles after last event"
// instead of resuming. Their own demo/bell_generic.mem stops at the same point.

// Event stream leaving vproc, gate id in `elem3[31:25]` (7 uppermost bits). Note that the first seven bits of
// 0xc8 are indeed 0x64 (Hadamard).

// CHECK-STREAM: [QX_START] {{.*}} elem3=c8000000
// CHECK-STREAM: [QX_START] {{.*}} elem3=d0000000
// CHECK-STREAM: quantum events : 2

// Pulses reaching qubit 0: Hadamard, then measure.

// CHECK-AWG:      [AWG]{{.*}} qubit[00]  gate=0x64  role=CTRL
// CHECK-AWG:      [AWG]{{.*}} qubit[00]  gate=0x68  role=CTRL
// CHECK-AWG:      qubit fires    : 2
// CHECK-AWG-NEXT: FIFO errors    : 0
