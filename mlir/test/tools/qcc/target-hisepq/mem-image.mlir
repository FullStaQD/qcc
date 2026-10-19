// REQUIRES: lld

// Smoke test for the full HiSEP-Q pipeline (see README next to `hisepq.ld`).

// RUN: qcc --target=hisepq --compile-to=native --binary %s -o %t.o
// RUN: ld.lld -T %project_source_dir/mlir/lib/Target/HiSEPQ/Scripts/hisepq.ld %t.o -o %t.elf
// RUN: hisepq-elf2mem %t.elf -o %t.mem
// RUN: FileCheck --input-file=%t.mem --match-full-lines %s

func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    qc.h %0 : !qc.qubit
    %m = qc.measure %0 : !qc.qubit -> i1
    aux.record_int %m : i1
    return
}

// Start address followed by hex-encoded instructions. (FileCheck's {{...}}
// cannot contain a {8} repetition, hence the loose `+`.)

// CHECK:      @00000020
// CHECK-NEXT: {{[0-9A-F]+}}
// CHECK-NEXT: {{[0-9A-F]+}}
