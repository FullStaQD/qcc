// RUN: qcc-opt %s | FileCheck %s
// RUN: qcc-opt %s --canonicalize | FileCheck %s --check-prefix=CANON

// Round trip of every `hlepgate` op.

func.func @all_ops(%reg : !prelimhlep.lin<i2>, %angle : f64) -> (!prelimhlep.lin<i2>, i1) attributes { prelimhlep.halo } {
    %q:2 = hlepgate.split %reg : !prelimhlep.lin<i2>
    %a = hlepgate.alloc
    %h = hlepgate.single h %a
    %p = hlepgate.single p(%angle) %h
    %c:2, %t = hlepgate.single x %q#1 ctrl(%q#0, %p)
    %m, %bit = hlepgate.measure %c#1
    hlepgate.sink %m
    %out = hlepgate.join %c#0, %t : !prelimhlep.lin<i2>
    return %out, %bit : !prelimhlep.lin<i2>, i1
}

// CHECK-LABEL: func.func @all_ops(
// CHECK-SAME:      [[REG:%.+]]: !prelimhlep.lin<i2>, [[ANGLE:%.+]]: f64)
// CHECK-NEXT:    [[Q:%.+]]:2 = hlepgate.split [[REG]] : !prelimhlep.lin<i2>
// CHECK-NEXT:    [[A:%.+]] = hlepgate.alloc
// CHECK-NEXT:    [[H:%.+]] = hlepgate.single h [[A]]
// CHECK-NEXT:    [[P:%.+]] = hlepgate.single p([[ANGLE]]) [[H]]
// CHECK-NEXT:    [[C:%.+]]:2, [[T:%.+]] = hlepgate.single x [[Q]]#1 ctrl([[Q]]#0, [[P]])
// CHECK-NEXT:    [[M:%.+]], [[BIT:%.+]] = hlepgate.measure [[C]]#1
// CHECK-NEXT:    hlepgate.sink [[M]]
// CHECK-NEXT:    [[OUT:%.+]] = hlepgate.join [[C]]#0, [[T]] : !prelimhlep.lin<i2>
// CHECK-NEXT:    return [[OUT]], [[BIT]]

// Folding: a gate cancels against its inverse on the same controls and
// target, and splitting and joining a register undo each other.

func.func @cancel(%c : !prelimhlep.lin<i1>, %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %s = hlepgate.single s %t
    %sdg = hlepgate.single sdg %s
    %c1, %x1 = hlepgate.single x %sdg ctrl(%c)
    %c2, %x2 = hlepgate.single x %x1 ctrl(%c1)
    return %c2, %x2 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// CANON-LABEL: func.func @cancel(
// CANON-SAME:      [[C:%.+]]: !prelimhlep.lin<i1>, [[T:%.+]]: !prelimhlep.lin<i1>)
// CANON-NEXT:    return [[C]], [[T]]

func.func @no_cancel(%c : !prelimhlep.lin<i1>, %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %x1 = hlepgate.single x %t
    %c2, %x2 = hlepgate.single x %x1 ctrl(%c)
    return %c2, %x2 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// CANON-LABEL: func.func @no_cancel(
// CANON:         hlepgate.single x
// CANON:         hlepgate.single x

func.func @rewire(%reg : !prelimhlep.lin<i2>) -> !prelimhlep.lin<i2> attributes { prelimhlep.halo } {
    %q:2 = hlepgate.split %reg : !prelimhlep.lin<i2>
    %joined = hlepgate.join %q#0, %q#1 : !prelimhlep.lin<i2>
    %r:2 = hlepgate.split %joined : !prelimhlep.lin<i2>
    %out = hlepgate.join %r#1, %r#0 : !prelimhlep.lin<i2>
    return %out : !prelimhlep.lin<i2>
}

// CANON-LABEL: func.func @rewire(
// CANON-SAME:      [[REG:%.+]]: !prelimhlep.lin<i2>)
// CANON-NEXT:    [[Q:%.+]]:2 = hlepgate.split [[REG]]
// CANON-NEXT:    [[OUT:%.+]] = hlepgate.join [[Q]]#1, [[Q]]#0
// CANON-NEXT:    return [[OUT]]
