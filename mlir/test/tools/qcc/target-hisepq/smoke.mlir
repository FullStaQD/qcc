// RUN: qcc --target=hisepq --compile-to=native %s | FileCheck %s

/// Prepare GHZ state without control flow.
func.func @main() attributes { qcc.entry_point } {
    %0 = qc.static 0 : !qc.qubit
    %1 = qc.static 1 : !qc.qubit
    %2 = qc.static 2 : !qc.qubit

    qc.h %0 : !qc.qubit

    qc.ctrl(%0) { qc.x %1 : !qc.qubit } : !qc.qubit
    qc.ctrl(%1) { qc.x %2 : !qc.qubit } : !qc.qubit

    %m0 = qc.measure %0 : !qc.qubit -> i1
    %m1 = qc.measure %1 : !qc.qubit -> i1
    %m2 = qc.measure %2 : !qc.qubit -> i1

    %a = arith.constant 42 : i64

    aux.record_int %a : i64
    aux.record_int %m0 : i1
    aux.record_int %m1 : i1
    aux.record_int %m2 : i1

    return
}

// FIXME: this has to be polished

// CHECK: main:
// CHECK:	vsetvli	a0, zero, e8, m1, ta, ma
// CHECK:	vmv.s.x	v8, zero
// CHECK:	li	a0, 1
// CHECK:	vmv.v.i	v9, 1
// CHECK:	vmv.v.i	v10, 2
// CHECK:	vsetvli	zero, a0, e8, m1, ta, ma
// CHECK:	qv.h	v8, zero, 0
// CHECK:	qv.cx	v8, v9, 0
// CHECK:	qv.cx	v9, v10, 0
// CHECK:	qv.mz	v8, zero, 0
// CHECK:	qv.mz	v9, zero, 0
// CHECK:	qv.mz	v10, zero, 0
// CHECK:	ret

// CHECK: _start:
// CHECK: 	lui	a0, %hi(__stack_top)
// CHECK: 	addi	a0, a0, %lo(__stack_top)
// CHECK: 	lui	a1, %hi(main)
// CHECK: 	addi	a1, a1, %lo(main)
// CHECK: 	#APP
// CHECK: 	mv	sp, a0
// CHECK: 	jalr	a1
